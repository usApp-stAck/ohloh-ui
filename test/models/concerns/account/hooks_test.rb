require 'test_helper'

class Account::HooksTest < ActiveSupport::TestCase
  fixtures :accounts, :invites

  class BeforeValidation < Account::HooksTest
    test 'must strip login email and name' do
      account = accounts(:user)
      account.login = 'login    '
      account.email = '     email'
      account.name = '    name    '
      account.save
      assert_equal 'login', account.login
      assert_equal 'email', account.email
      assert_equal 'name', account.name
    end

    test 'must set name to login when it is blank' do
      account = build(:account)
      account.name = ''
      account.valid?
      assert_equal account.login, account.name
    end
  end

  class BeforeCreate < Account::HooksTest
    test 'must set activation code to random hash' do
      account = create(:account)
      assert_not_empty account.activation_code
      assert_equal 40, account.activation_code.length
      assert_nil account.activation_code.match(/[^a-z0-9]/)
    end

    test 'must populate salt' do
      account = build(:account)
      account.save!

      assert_equal true, account.salt.present?
    end
  end

  class BeforeSave < Account::HooksTest
    test 'must not change salt' do
      account = accounts(:user)
      account.password = 'new_password'
      account.password_confirmation = 'new_password'
      original_salt = account.salt

      account.save!

      assert_equal original_salt, account.salt
    end

    test 'must not change crypted_password when password is blank' do
      account = accounts(:uber_data_crawler)
      account.password = nil
      account.password_confirmation = nil
      original_crypted_password = account.crypted_password

      account.save!

      assert_equal original_crypted_password, account.crypted_password
    end

    test 'must change crypted_password if password is not blank' do
      account = accounts(:uber_data_crawler)
      account.password = 'new_password'
      account.password_confirmation = 'new_password'
      original_crypted_password = account.crypted_password

      account.save!

      assert_not_equal original_crypted_password, account.crypted_password
    end

    test 'must encrypt email when it changes' do
      account = accounts(:user)
      original_email_md5 = account.email_md5
      account.email = Faker::Internet.email
      account.save!

      assert_not_equal original_email_md5, account.email_md5
    end

    test 'must not encrypt email when it has not changed' do
      account = accounts(:user)
      account.expects(:encrypt_email).never
      account.save!
    end
  end

  class BeforeDestroy < Account::HooksTest
    test 'should destroy dependencies when marked as spam' do
      account = accounts(:user)
      Account::Authorize.any_instance.stubs(:spam?).returns(true)
      account.topics.update_all(posts_count: 0)
      assert_equal 3, account.topics.count
      assert_not_nil account.person
      assert_equal 1, account.positions.count
      account.save!
      account.reload
      assert_equal 0, account.topics.count
      assert_nil account.person
      assert_equal 0, account.positions.count
    end

    test 'should rollback when destroy dependencies raises an exception' do
      account = accounts(:user)
      Account::Authorize.any_instance.stubs(:spam?).returns(true)
      Account.any_instance.stubs(:api_keys).raises(ActiveRecord::Rollback)
      account.topics.update_all(posts_count: 0)
      assert_equal 3, account.topics.count
      assert_not_nil account.person
      assert_equal 1, account.positions.count
      account.save
      account.reload
      assert_equal 3, account.topics.count
      assert_not_nil account.person
      assert_equal 1, account.positions.count
    end

    test 'should destroy dependencies before account destroy' do
      account = accounts(:user)
      assert_equal 1, account.positions.count
      assert_equal 5, account.posts.count
      assert_equal 0, Account.find_or_create_anonymous_account.posts.count
      assert_difference('DeletedAccount.count', 1) do
        account.destroy
      end
      assert_equal 0, account.positions.count
      assert_equal 0, account.posts.count
      assert_equal 5, Account.find_or_create_anonymous_account.posts.count
    end
  end

  class AfterCreate < Account::HooksTest
    test 'must change invitee id and activated date' do
      account = build(:account)
      account.no_email = false
      invite = invites(:user)
      invitee_id = invite.invitee_id
      account.invite_code = invite.activation_code
      account.save

      assert_not_equal invites(:user).reload.invitee_id, invitee_id
      assert_equal invites(:user).invitee_id, account.id
    end

    test 'must create person for non spam account' do
      account = build(:account, level: Account::DEFAULT_LEVEL)
      account.no_email = false

      assert_difference('Person.count', 1) do
        account.save
      end
    end

    test 'must not create person for spam account' do
      account = build(:account, level: Account::SPAMMER_LEVEL)
      account.no_email = false

      assert_no_difference('Person.count') do
        account.save
      end
    end

    test 'should rollback when notification raises an error' do
      skip('TODO: AccountNotifier')

      account = build(:account, level: Account::DEFAULT_LEVEL)
      account.no_email = true
      AccountNotifier.stubs(:deliver_signup_notification)
                     .raises(Net::SMTPSyntaxError.new('Bad recipient address syntax'))

      assert_no_difference('Person.count') do
        Account.transaction do
          account.save
        end
      end

      assert_equal 1, account.errors.size
      # assert_equal ["The Black Duck Open Hub could not send
      # registration email to <strong class='red'>uber@ohloh.net</strong>.
      # Invalid Email Address provided."], account.errors['email']
    end
  end

  class AfterUpdate < Account::HooksTest
    test 'should schedule organization analysis on update' do
      skip('FIXME: add test when implementing schedule_analysis')
    end
  end

  class AfterSave < Account::HooksTest
    test 'must update persons effective_name after save' do
      account = accounts(:user)
      assert_equal 'Robin Luckey', account.person.effective_name
      account.save!
      assert_equal 'user Luckey', account.person.effective_name
    end
  end
end
