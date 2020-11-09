# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "jsonapi_mapper/version"

Gem::Specification.new do |spec|
  spec.name          = "jsonapi_mapper"
  spec.version       = JsonapiMapper::VERSION
  spec.authors       = ["nubis"]
  spec.email         = ["nb@bitex.la"]

  spec.summary       = %q{Sanitize and Map jsonapi documents straight into activemodels}
  spec.description   = %q{
    Sanitizes a jsonapi Document and maps it to ActiveRecord,
    creating or updating as needed.
    Prevents mistakes when assigingng attributes or referring to 
    unscoped relationships.
  }
  spec.homepage      = "https://github.com/bitex-la/jsonapi-mapper"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", '~> 5.0', '>= 5.0.0'
  spec.add_dependency "activemodel",'~> 5.0', '>= 5.0.0'

  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "activerecord", '~> 5.1', '>= 5.1.4'
  spec.add_development_dependency "sqlite3", "~> 1.0", ">= 1.0.0"
  spec.add_development_dependency "byebug", "~> 6.0", ">= 6.0.0"
end
