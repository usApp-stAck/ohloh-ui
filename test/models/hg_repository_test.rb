require 'test_helper'

class HgRepositoryTest < ActiveSupport::TestCase
  it 'must find return hg adapter' do
    repository = create(:hg_repository)
    repository.source_scm_class.must_equal OhlohScm::Adapters::HglibAdapter
  end
end
