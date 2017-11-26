# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "jsonapi_mapper/version"

Gem::Specification.new do |spec|
  spec.name          = "jsonapi_mapper"
  spec.version       = JsonapiMapper::VERSION
  spec.authors       = ["nubis"]
  spec.email         = ["nb@bitex.la"]

  spec.summary       = %q{Map jsonapi documents straight into activemodels}
  spec.description   = %q{
    Can be used like strong params but for creating/updating a number of
    active models. Main usage is parsing JSONAPI requests with multiple entities.
  }
  spec.homepage      = "https://github.com/bitex-la/jsonapi_mapper"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", '~> 4.2', '>= 4.2.0'
  spec.add_dependency "activemodel",'~> 4.2', '>= 4.2.0'

  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "activerecord", '~> 4.2', '>= 4.2.0'
  spec.add_development_dependency "sqlite3", "~> 1.0", ">= 1.0.0"
  spec.add_development_dependency "byebug", "~> 6.0", ">= 6.0.0"
end
