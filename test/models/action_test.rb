require 'test_helper'

class ActionTest < ActiveSupport::TestCase
  let(:admin_account) { accounts(:admin) }
  let(:linux_project) { projects(:linux) }

  it 'test account required' do
    assert_no_difference 'Action.count' do
      action = Action.create
      action.errors.must_include(:account)
    end
  end

  it 'test action requires something to do' do
    assert_no_difference 'Action.count' do
      action = Action.create(account: admin_account)
      action.errors.must_include(:payload_required)
    end
  end

  it 'test create succeeds for claim' do
    assert_difference 'Action.count' do
      person = people(:joe)
      action = Action.create!(account: admin_account, claim: person)
      action.claim.must_equal person
      action.account.must_equal admin_account
    end
  end

  it 'test create succeeds for stacked project' do
    assert_difference 'Action.count' do
      action = Action.create(account: admin_account, stack_project: linux_project)
      action.stack_project.must_equal linux_project
    end
  end

  it 'test command for claim' do
    assert_difference 'Action.count' do
      action_param = "claim_#{people(:joe).id}"
      action = Action.create!(account: admin_account, _action: action_param)
      action.account.must_equal admin_account
      action.claim.must_equal people(:joe)
    end
  end

  it 'test command for claim of person with no project' do
    assert_no_difference 'Action.count' do
      action_param = "claim_#{people(:kyle).id}"
      action = Action.create(account: admin_account, _action: action_param)
      action.errors.include?(:claim).must_equal true
      action.errors.must_include(:claim)
    end
  end

  it 'test command for claim of person with no name' do
    assert_no_difference 'Action.count' do
      action_param = "claim_#{people(:robin).id}"
      action = Action.create(account: admin_account, _action: action_param)
      action.errors.must_include(:claim)
    end
  end

  it 'test command for stacked project' do
    assert_difference 'Action.count' do
      action_param = "stack_#{linux_project.id}"
      action = Action.create!(account: admin_account, _action: action_param)
      action.account.must_equal admin_account
      action.stack_project.must_equal linux_project
    end
  end

  it 'test run with newly activated account' do
    action = Action.create!(account: admin_account, _action: "stack_#{linux_project.id}", status: 'after_activation')
    action.run
    admin_account.stack_core.default.projects.must_include(linux_project)
    action.status.must_equal Action::STATUSES[:remind]
  end
end
