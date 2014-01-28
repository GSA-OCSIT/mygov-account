require 'spec_helper'

describe Notification do
  before do
    @valid_attributes = {
      :id => 1234,
      :subject => 'Test',
      :received_at => Time.now,
      :body => 'This is a test notification',
      :notification_type => 'my-app-1'
    }
    create_approved_beta_signup('joe@citizen.org')
    @user = User.create!(:email => 'joe@citizen.org', :password => 'Password1')
    @user.profile = Profile.new(:first_name => 'Joe', :last_name => 'Citizen')
    @app = App.create!(:name => 'App1', :redirect_uri => 'http://localhost/')
  end
  %w{subject received_at user_id}.each do |e|
    it { should validate_presence_of(e).with_message(/can't be blank/)}
  end
   it { should belong_to :user }
   it { should belong_to :app }

  it "should create a new notification with valid attributes" do
    Notification.create!(@valid_attributes.merge(:user_id => @user.id, :app_id => @app.id), :as => :admin)
  end

  context "when creating a new notification" do
    let(:setting1) { FactoryGirl.create(:notification_setting, delivery_type: 'text') }
    let(:setting2) { FactoryGirl.create(:notification_setting, delivery_type: 'dashboard') }

    let(:mock_setting1) { mock_model(NotificationSetting, notification_type: @notification.notification_type, delivery_type: 'text') }
    let(:mock_setting2) { mock_model(NotificationSetting, notification_type: @notification.notification_type, delivery_type: 'dashboard') }
    let(:mock_setting3) { mock_model(NotificationSetting, notification_type: @notification.notification_type, delivery_type: 'email') }

    before do
      Twilio::REST::Client.stub(:new)
      @notification = FactoryGirl.build(:notification, @valid_attributes)
      @notification.assign_attributes({:app_id => @app.id}, as: :admin)
      @notification.assign_attributes({:user_id => 123456}, as: :admin)
    end

    context 'with delivery types' do
      it 'should invoke a delivery for every delivery type for the application' do
        settings = [mock_setting1, mock_setting2, mock_setting3]
        @notification.stub_chain(:user, :notification_settings, :where).and_return(settings)
        Resque.should_receive(:enqueue).with(NotificationText, @notification.id).once
        Resque.should_receive(:enqueue).with(NotificationDashboard, @notification.id).once
        Resque.should_receive(:enqueue).with(NotificationEmail, @notification.id).once
        @notification.save
      end
    end

    context 'without any delivery types' do
      it 'should not invoke a delivery' do
        @notification.stub_chain(:user, :notification_settings, :where).and_return([])
        Resque.should_not receive(:enqueue)
        @notification.save
      end
    end

    context "when creating a notification without an app" do
      it "should send an email to the user with the notification content" do
        notification = Notification.create!(@valid_attributes.merge(:user_id => @user.id), :as => :admin)
        email = ActionMailer::Base.deliveries.first
        email.should_not be_nil
        email.from.should == [Mail::Address.new(DEFAULT_FROM_EMAIL).address]
        email.to.should == [@user.email]
        email.subject.should == "[MYUSA] #{notification.subject}"
        email.parts.map do |part|
          expect(part.body).to include("Hello, #{@user.profile.first_name}")
          expect(part.body).to include('A notification for you from MyUSA')
          expect(part.body).to include("#{@valid_attributes[:body]}")
        end
      end
    end

    context "when creating a notification with an app" do
      it "should send an email to the user with the notification content identifying the sending application" do
        notification = Notification.create!(@valid_attributes.merge(:user_id => @user.id, :app_id => @app.id, :body => "<p>#{@valid_attributes[:body]}</p>"), :as => :admin)
        email = ActionMailer::Base.deliveries.first
        email.should_not be_nil
        email.from.should == [Mail::Address.new(DEFAULT_FROM_EMAIL).address]
        email.to.should == [@user.email]
        email.subject.should == "[MYUSA] [#{notification.app.name}] #{notification.subject}"
        email.parts.map do |part|
          expect(part.body).to include("Hello, #{@user.profile.first_name}")
          expect(part.body).to include("The \"#{notification.app.name}\" MyUSA application has sent you the following message")
          expect(part.body).to include("#{@valid_attributes[:body]}")
        end
        expect(email.html_part.body).to_not include('&lt;')
      end
    end
  end
end
