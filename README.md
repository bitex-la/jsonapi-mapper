# JsonapiMapper

Sanitizes a jsonapi Document and maps it to ActiveRecord, creating or updating as needed.
- Prevents assiginging unexpected attributes on your records.
- Prevents unscoped queries when creating/updating records.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'jsonapi_mapper'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install jsonapi_mapper

## Usage

See the specs directory for more examples.

```ruby
      class Person < ActiveRecord::Base
        belongs_to :parent, class_name: 'Person'
        has_many :children, class_name: 'Person', foreign_key: 'parent_id'
        belongs_to :pet, class_name: 'PetDog'
      end

      class PetDog < ActiveRecord::Base
        has_one :person, foreign_key: 'pet_id'
      end

      # This document should create a person and several associations.
      # Notice how these not-persisted resources can be referenced using
      # an internal id, which starts with @
      # The local @ ids shall be replaced with proper server assigned ids
      # once the resources are persisted.
      document = {
        data: {
          type: 'people',
          attributes: { name: 'ian', admin: true },
          relationships: {
            pet: { data: { type: 'pet_dogs', id: '@1' }},
            parent: { data: { type: 'people', id: '@1' }},
            children: { data: [
              { type: 'people', id: '@2' },
              { type: 'people', id: '@3' },
            ]},
          }
        },
        included: [
          { type: 'people', id: '@1', attributes: { name: 'ana', admin: true } },
          { type: 'people', id: '@2', attributes: { name: 'bob', admin: true } },
          { type: 'people', id: '@3', attributes: { name: 'zoe', admin: true } },
          { type: 'pet_dogs', id: '@1', attributes: { name: 'ace', age: 11 } }
        ]
      }

      # The mapper whitelists which types should be expected from the
      # jsonapi document. It also whitelists attributes and relationship names.
      # The last item of the attributes list is a Hash to be used as 'scope'
      # when attempting to fetch and/or modify any resource.
      mapper = JsonapiMapper.doc(document,
        people: [:name, :pet, :parent, :children, country: 'argentina'],
        pet_dogs: [:name, country: 'argentina']
      )

      # The document data lives in mapper.data
      # It's always an array, even if the document had a single resource.
      # If you want to check wether the document had a single resource
      # or a collection as its primary data you can use the following methods.
      mapper.collection? # Was primary document data a collection?
      mapper.single? # Was primary document data a single resource?

      person = mapper.data.first

      # The rest of the included resources live in mapper.included
      others = mapper.included 

      # Attempts to save both data and included. Returns false if there
      # were any validation errors.
      mapper.save_all 
      
      # Four people have been created
      Person.count.should == 4

      # All of them from 'argentina' according to the provided scope.
      Person.where(country: 'argentina').count.should == Person.count

      # The 'admin' field was not set, because it wasn't in the mapper list.
      Person.where(admin: true).count.should == 0
      
      # This other document tries to update a bob's name and parent.
      # And it also creates a new dow and assigns it as pet for 'bob' and 'ana'
      other_document = {
        data: {
          type: 'people',
          id: '1',
          attributes: { name: 'rob' },
          relationships: {
            pet: { data: { type: 'pet_dogs', id: '@1' }},
            parent: { data: { type: 'people', id: '2' }},
          }
        },
        included: [
          { 
            type: 'people',
            id: ana.id,
            relationships: {
              pet: { data: { type: 'pet_dogs', id: '@1' }},
            }
          },
          { type: 'pet_dogs', id: '@1', attributes: { name: 'ace' } }
        ]
      }

      mapper = JsonapiMapper.doc other_document,
        people: [:name, :pet, :parent, country: 'uruguay'],
        pet_dogs: [:name, country: 'uruguay']

      mapper.save_all

      # Is dangerous to use unscoped queries
      # For those rare occassions where you don't need them they can be disabled.
      # The JsonapiMapper.doc_unsafe! method receives an argument with the names
      # of all the types for which a scope is not required.
      JsonapiMapper.doc_unsafe! document,
        [:pet_dogs],
        people: [:name, :pet, :parent, country: 'uruguay'],
        pet_dogs: [:name]

      # If you're needing to 'translate' between your jsonapi document names
      # and your ActiveRecord class and column names, you can do it like so:
      # Notice how the second hash has translations for type and attribute names.
      mapper = JsonapiMapper.doc(document, {
        persons: [:handle, :dog, :parental_figure, country: 'uruguay'],
        pets: [:nickname, country: 'uruguay']
      },
      { types: { persons: Person, pets: PetDog },
        attributes: {
          persons: {handle: :name, dog: :pet, parental_figure: :parent},
          pets: {nickname: :name},
        }  
      }).save_all
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome here.

## Code Status

[![Build Status](https://circleci.com/gh/bitex-la/jsonapi-mapper.png)](https://circleci.com/gh/bitex-la/jsonapi-mapper)

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
