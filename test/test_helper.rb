ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Swap a class method for the duration of the block, then restore it.
    # Keeps service-orchestration tests hermetic (no network, no Chrome).
    def stub_class_method(klass, method, impl)
      original = klass.method(method)
      klass.define_singleton_method(method, impl)
      yield
    ensure
      klass.define_singleton_method(method, original)
    end
  end
end
