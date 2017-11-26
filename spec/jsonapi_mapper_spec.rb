require "spec_helper"

class Person < ActiveRecord::Base
  belongs_to :parent, class_name: 'Person'
  has_many :children, class_name: 'Person', foreign_key: 'parent_id'
  belongs_to :pet, class_name: 'PetDog'
end

class PetDog < ActiveRecord::Base
  has_one :person, foreign_key: 'pet_id'
end

describe "Reads documents into models" do
  before(:all){ setup_database! }
  after(:all){ cleanup_database! }
  before(:each) do
    run_migration do
      create_table(:people, force: true) do |t|
        t.string :country
        t.references :parent
        t.references :pet
        t.string :name
        t.boolean :admin, null: false, default: false
      end

      create_table(:pet_dogs, force: true) do |t|
        t.string :country
        t.references :person
        t.string :name
        t.integer :age
      end
    end
  end

  let(:bob){ Person.create(name: 'bob', country: 'uruguay') }
  let(:ana){ Person.create(name: 'ana', country: 'uruguay') }
  let(:ace){ PetDog.create(name: 'ace', country: 'uruguay') }
  let(:ari){ Person.create(name: 'ari', country: 'belgium') }
  let(:doc_updating_bob_ana_and_adding_pet) do
    {
      data: {
        type: 'people',
        id: bob.id,
        attributes: { name: 'rob', admin: true },
        relationships: {
          pet: { data: { type: 'pet_dogs', id: '@1' }},
          parent: { data: { type: 'people', id: ana.id }},
        }
      },
      included: [
        { 
          type: 'people',
          id: ana.id,
          relationships: {
            pet: { data: { type: 'pet_dogs', id: '@1' }},
            parent: { data: { type: 'people', id: bob.id }},
          }
        },
        { type: 'pet_dogs', id: '@1', attributes: { name: 'ace' } }
      ]
    }
  end

  it "creates a new resource with included associations" do
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

    mapper = JsonapiMapper.doc document,
      people: [:name, :pet, :parent, :children, country: 'argentina'],
      pet_dogs: [:name, country: 'argentina']

    person = mapper.data
    person.save
    person.reload.tap do |p|
      p.pet.name.should == 'ace'
      p.pet.age.should be_nil
      p.parent.name.should == 'ana'
      p.children.collect(&:name).should == %w(bob zoe)
    end

    Person.count.should == 4
    Person.where(country: 'argentina').count.should == Person.count
    Person.where(admin: true).count.should == 0
    PetDog.count.should == 1
  end

  it "updates resources and relates them together" do
    mapper = JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
      people: [:name, :pet, :parent, country: 'uruguay'],
      pet_dogs: [:name, country: 'uruguay']

    mapper.save_all

    bob.reload.parent.should == ana
    ana.reload.parent.should == bob
    bob.name.should == 'rob'
    bob.pet.name.should == 'ace'
    bob.pet.should == ana.pet
  end

  describe "when whitelisting" do
    it "ignores classes that were not permitted" do
      mapper = JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
        people: [:name, :pet, :parent, country: 'uruguay']
      mapper.data.pet.should be_nil
      mapper.included.first.pet.should be_nil

      mapper.save_all

      bob.reload.pet.should be_nil
      ana.reload.pet.should be_nil
    end

    it "ignores relationships that were not permitted" do
      mapper = JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
        people: [:name, :pet, country: 'uruguay'],
        pet_dogs: [:name, country: 'uruguay']
        
      mapper.save_all

      bob.reload.parent.should be_nil
      ana.reload.parent.should be_nil
    end

    it "ignores attributes that were not permitted" do
      mapper = JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
        people: [:pet, country: 'uruguay']
        
      mapper.save_all

      bob.reload.name.should == 'bob'
    end

    it "raises when trying to whitelist a missing class" do
      expect do
        mapper = JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
          bogus_class: [:bogus_attribute, country: 'uruguay']
      end.to raise_exception NameError
    end

    it "raises when trying to whitelist a missing attribute" do
      expect do
        mapper = JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
          people: [:bogus_attribute, country: 'uruguay']
      end.to raise_exception NoMethodError
    end
  end

  describe "when setting up relationships" do
    it "can relate the same new object to several objects" do
      bob.pet.should be_nil
      ana.pet.should be_nil

      mapper = JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
        people: [:name, :pet, :parent, country: 'uruguay'],
        pet_dogs: [:name, country: 'uruguay']

      mapper.save_all

      bob.reload.pet.should == ana.reload.pet
      bob.pet.should be_a PetDog
    end

    it "can reference a new resource from included resources" do
      document = {
        data: { type: 'people', id: '@1', attributes: {name: 'bob'} },
        included: [
          { type: 'pet_dogs',
            id: ace.id,
            relationships: { 
              person: {data: {id: '@1', type: 'people' }}
            }
          }
        ]
      }

      ace.person.should be_nil
      mapper = JsonapiMapper.doc document,
        people: [:name, country: 'uruguay'],
        pet_dogs: [:person, country: 'uruguay']

      mapper.save_all

      ace.reload.person.should == mapper.data.reload
    end

    it "can create and relate only happening in inner relationships" do
      document = {
        data: { type: 'people', id: bob.id, attributes: {} },
        included: [
          { 
            type: 'people',
            id: ana.id,
            relationships: { pet: { data: { type: 'pet_dogs', id: '@1' }}}
          },
          { type: 'pet_dogs', id: '@1', attributes: { name: 'ace' } }
        ]
      }

      ana.pet.should be_nil 
      mapper = JsonapiMapper.doc document,
        people: [:name, :pet, :parent, country: 'uruguay'],
        pet_dogs: [:name, country: 'uruguay']

      mapper.save_all

      ana.reload.pet.should be_a PetDog
    end

    it "raises RecordNotFound when local referenced resource is not included" do
      document = {
        data: {
          type: 'people',
          id: bob.id,
          attributes: { name: 'rob', admin: true },
          relationships: { pet: { data: { type: 'pet_dogs', id: '@1' }}}
        },
        included: [ { type: 'people', id: ana.id } ]
      }

      expect do
        JsonapiMapper.doc document,
          people: [:name, :pet, :parent, country: 'uruguay'],
          pet_dogs: [:name, country: 'uruguay']
      end.to raise_exception ActiveRecord::RecordNotFound
    end

    it "raises when remote resource could not be found" do
      document = {
        data: {
          type: 'people',
          id: bob.id,
          relationships: { pet: { data: { type: 'pet_dogs', id: '1' }}}
        }
      }

      expect do
        JsonapiMapper.doc document,
          people: [:name, :pet, :parent, country: 'uruguay'],
          pet_dogs: [:name, country: 'uruguay']
      end.to raise_exception ActiveRecord::RecordNotFound
    end

    it "allows rules to be only scope when just relating" do
      document = {
        data: {
          type: 'people',
          id: bob.id,
          relationships: { pet: { data: { type: 'pet_dogs', id: ace.id }}}
        }
      }

      bob.pet.should be_nil
      JsonapiMapper.doc(document,
        people: [:pet, country: 'uruguay'],
        pet_dogs: [country: 'uruguay']
      ).save_all

      bob.reload.pet.should == ace
    end

    it "bypasses scope when allowing to set via integer '_id' field" do
      document = {
        data: {
          type: 'people',
          id: bob.id,
          attributes: { pet_id: ace.id.to_s },
        }
      }

      bob.pet.should be_nil

      JsonapiMapper.doc(document, people: [:pet_id, country: 'uruguay'])
        .save_all

      bob.reload.pet.should == ace
    end


    it "does not allow overriding a relationship from a field" do
      document = {
        data: {
          type: 'people',
          id: bob.id,
          attributes: { pet: ace.id.to_s },
        }
      }

      expect do
        JsonapiMapper.doc(document, people: [:pet, country: 'uruguay'])
          .save_all
      end.to raise_exception ActiveRecord::AssociationTypeMismatch
    end
  end

  describe 'when using the scope' do
    it "cannot update resources outside given scope" do
      document = {
        data: { type: 'people', id: ari.id, attributes: { name: 'ariel' } }
      }

      expect do
        JsonapiMapper.doc(document, people: [:name, country: 'uruguay'])
      end.to raise_exception ActiveRecord::RecordNotFound
    end

    it "cannot use resources outside given scope for relationships" do
      pending
      fail
    end

    it "raises if no scope was given" do
      # This was a developer's mistake.
      pending
      fail
    end

    it "allows unscoped relationships, but in the most obnoxious way" do
      pending
      fail
    end

    it "cannot change the scope attribute of the main resource" do
      pending
      fail
    end

    it "cannot change the scope attribute of included attributes" do
      pending
      fail
    end
  end

  describe "when validating the dsl" do
    it "raises if keys are not string or symbol" do
      # This was a developer's mistake.
      pending
      fail
    end

    it "raises if scope was there but wasn't a hash" do
      pending
      fail
    end
  end

  describe "when remapping name" do
    it "remaps class names" do
      pending
      fail
    end

    it "remaps attribute names" do
      pending
      fail
    end
  end

  describe "when handling corner cases of invalid data" do
    it "supports missing main data" do
      pending
      fail
    end

    it "supports missing included" do
      pending
      fail
    end

    it "does not blow up when document is malformed" do
      pending
      fail
    end

    it "does not blow up when data is an array" do
      pending
      fail
    end

    it "does not blow up when data is messed up" do
      pending
      fail
    end

    it "ignores bogus attributes sent by customer" do
      pending
      fail
    end
  end
end
