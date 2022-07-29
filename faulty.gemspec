# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'faulty/version'

Gem::Specification.new do |spec|
  spec.name = 'faulty'
  spec.version = Faulty.version
  spec.authors = ['Justin Howard']
  spec.email = ['jmhoward0@gmail.com']
  spec.licenses = ['MIT']
  spec.summary = 'Fault-tolerance tools for ruby based on circuit-breakers'
  spec.homepage = 'https://github.com/ParentSquare/faulty'

  rubydoc = 'https://www.rubydoc.info/gems'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata['documentation_uri'] = "#{rubydoc}/#{spec.name}/#{spec.version}"

  spec.files = Dir['lib/**/*.rb', '*.md', '*.txt', '.yardopts']
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.3'

  spec.add_runtime_dependency 'concurrent-ruby', '~> 1.0'

  # Only essential development tools and dependencies go here.
  # Other non-essential development dependencies go in the Gemfile.
  spec.add_development_dependency 'connection_pool', '~> 2.0'
  spec.add_development_dependency 'json'
  spec.add_development_dependency 'redis', '>= 3.0'
  spec.add_development_dependency 'rspec', '~> 3.8'
  spec.add_development_dependency 'timecop', '>= 0.9'
end
