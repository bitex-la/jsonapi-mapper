require "spec_helper"

class Person < ActiveRecord::Base
  belongs_to :parent, class_name: 'Person'
  has_many :children, class_name: 'Person', foreign_key: 'parent_id'
  belongs_to :pet, class_name: 'PetDog'
end

class PetDog < ActiveRecord::Base
  has_one :person, foreign_key: 'pet_id'
  validates :name, presence: true
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

    mapper.save_all

    mapper.should be_single
    mapper.data.reload.tap do |p|
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

  it "updates and creates a full collection" do
    document = {
      data: [
        {
          type: 'people',
          attributes: { name: 'ian', admin: true },
          relationships: {
            pet: { data: { type: 'pet_dogs', id: '@1' }},
            parent: { data: { type: 'people', id: '@1' }},
            children: { data: [
              { type: 'people', id: bob.id },
              { type: 'people', id: '@3' },
            ]},
          }
        },
        { type: 'people', id: '@1', attributes: { name: 'ana' } },
        { type: 'people', id: bob.id, attributes: { name: 'rob' } },
        { type: 'people', id: '@3', attributes: { name: 'zoe'} },
      ],
      included: [
        { type: 'pet_dogs', id: '@1', attributes: { name: 'ace', age: 11 } }
      ]
    }

    mapper = JsonapiMapper.doc document,
      people: [:name, :pet, :parent, :children, country: 'uruguay'],
      pet_dogs: [:name, country: 'uruguay']
    mapper.should be_collection
    mapper.save_all

    bob.reload.name.should == 'rob'
    mapper.data.first.pet.should == PetDog.first
  end

  describe "when whitelisting" do
    it "ignores types that were not permitted" do
      mapper = JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
        people: [:name, :pet, :parent, country: 'uruguay']
      mapper.should be_single
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
      mapper.should be_single
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
    let(:ari){ Person.create(name: 'ari', country: 'belgium') }

    it "cannot update resources outside given scope" do
      document = {
        data: { type: 'people', id: ari.id, attributes: { name: 'ariel' } }
      }

      expect do
        JsonapiMapper.doc(document, people: [:name, country: 'uruguay'])
      end.to raise_exception ActiveRecord::RecordNotFound
    end

    it "cannot use resources outside given scope for relationships" do
      document = {
        data: {
          type: 'pet_dogs',
          id: ace.id,
          relationships: { person: { data: { type: 'people', id: ari.id }}}
        }
      }
      expect do
        JsonapiMapper.doc document,
          people: [country: 'uruguay'],
          pet_dogs: [:person, country: 'uruguay']
      end.to raise_exception ActiveRecord::RecordNotFound
    end

    it "raises if no scope was given" do
      expect do
        JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
          people: [:name, :pet, :parent, country: 'uruguay'],
          pet_dogs: [:name]
      end.to raise_exception JsonapiMapper::RulesError
    end

    it "allows unscoped relationships, but in the most obnoxious way" do
      expect do
        JsonapiMapper.doc_unsafe! doc_updating_bob_ana_and_adding_pet,
          [:pet_dogs],
          people: [:name, :pet, :parent, country: 'uruguay'],
          pet_dogs: [:name]
      end.not_to raise_exception 
    end

    it "cannot change the scope attribute of the main resource" do
      expect do
        JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
          people: [:country, country: 'uruguay'],
          pet_dogs: [:name, country: 'uruguay']
      end.to raise_exception JsonapiMapper::RulesError
    end

    it "cannot change the scope attribute of included attributes" do
      expect do
        JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
          people: [:name, country: 'uruguay'],
          pet_dogs: [:country, country: 'uruguay']
      end.to raise_exception JsonapiMapper::RulesError
    end
  end

  describe "when validating the dsl" do
    it "raises if attributes are not string or symbol" do
      expect do
        JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
          people: [11, country: 'uruguay'],
          pet_dogs: [['fubar'], country: 'uruguay']
      end.to raise_exception JsonapiMapper::RulesError
    end

    it "raises if scope was there but wasn't a hash" do
      expect do
        JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
          people: [11],
          pet_dogs: [['fubar']]
      end.to raise_exception JsonapiMapper::RulesError
    end
  end

  describe "when remapping name" do
    it "remaps class names and attribute names" do
      document = {
        data: {
          type: 'persons',
          id: bob.id,
          attributes: { handle: 'rob' },
          relationships: {
            dog: { data: { type: 'pets', id: '@1' }},
            parental_figure: { data: { type: 'persons', id: ana.id }},
          }
        },
        included: [
          { 
            type: 'persons',
            id: ana.id,
            relationships: {
              dog: { data: { type: 'pets', id: '@1' }},
              parental_figure: { data: { type: 'persons', id: bob.id }},
            }
          },
          { type: 'pets', id: '@1', attributes: { nickname: 'ace' } }
        ]
      }
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

      bob.reload.pet.should == ana.reload.pet
      bob.pet.name.should == 'ace'
      bob.name.should == 'rob'
    end

    it "cannot write the scope attribute even if renamed" do
      document = {
        data: { type: 'pet_dogs', attributes: { nationality: 'narnia' } },
      }
      expect do
        mapper = JsonapiMapper.doc(document, {
          pet_dogs: [:nationality, country: 'uruguay']
        },
        { 
          attributes: { pet_dogs: {nickname: :name, nationality: :country} }
        }).save_all
      end.to raise_exception JsonapiMapper::RulesError
    end
  end

  describe "when saving all data" do
    it "returns true and saves when everything was valid" do
      mapper = JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
        people: [:name, :pet, :parent, country: 'uruguay'],
        pet_dogs: [:name, country: 'uruguay']

      mapper.save_all.should be_truthy
      bob.reload.parent.should == ana
      ana.reload.parent.should == bob
    end

    it "returns false and doesn't save if any resource had validation errors" do
      mapper = JsonapiMapper.doc doc_updating_bob_ana_and_adding_pet,
        people: [:name, :pet, :parent, country: 'uruguay'],
        pet_dogs: [country: 'uruguay']

      mapper.save_all.should be_falsey
      bob.reload.parent.should be_nil
      ana.reload.parent.should be_nil
    end
  end

  describe "when handling corner cases of invalid data" do
    it "supports missing main data" do
      document = {
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

    it "supports missing included" do
      document = {
        data: { type: 'people', id: bob.id, attributes: {name: 'rob'} },
      }

      JsonapiMapper.doc(document, people: [:name, country: 'uruguay']).save_all

      bob.reload.name.should == 'rob'
    end

    it "does not blow up when document is malformed" do
      document = {
        whatsaaap: { type: 'people', id: bob.id, attributes: {name: 'rob'} },
        data: { tope: 'people', id: bob.id, att: {name: 'rob'} },
      }

      JsonapiMapper.doc(document, people: [:name, country: 'uruguay']).save_all

      bob.reload.name.should == 'bob'
    end

    it "does not blow up when data is an array" do
      JsonapiMapper.doc({ data: [9,9] }, people: [:name, country: 'uruguay'])
        .save_all
      bob.reload.name.should == 'bob'
    end

    it "ignores bogus attributes sent by customer" do
      document = {
        data: { type: 'people', id: bob.id, attributes: {bogus: 'bogus'} },
      }

      JsonapiMapper.doc(document, people: [:name, country: 'uruguay'])
        .save_all

      bob.reload.name.should == 'bob'
    end

    it "ignores invalid relationships" do
      document = {
        data: {
          type: 'people',
          id: bob.id,
          attributes: {bogus: 'bogus'},
          relationships: 2323
        }
      }

      JsonapiMapper.doc(document, people: [:name, country: 'uruguay'])
        .save_all

      bob.reload.name.should == 'bob'
    end

    it "ignores invalid attributes" do
      document = {
        data: { type: 'people', id: bob.id, attributes: 33 }
      }

      JsonapiMapper.doc(document, people: [:name, country: 'uruguay'])
        .save_all

      bob.reload.name.should == 'bob'
    end

    it "works with documents that have strings as keys" do
      stringy_doc = doc_updating_bob_ana_and_adding_pet.deep_stringify_keys
      mapper = JsonapiMapper.doc stringy_doc,
        people: [:name, :pet, :parent, country: 'uruguay'],
        pet_dogs: [:name, country: 'uruguay']

      mapper.save_all

      bob.reload.parent.should == ana
      ana.reload.parent.should == bob
      bob.name.should == 'rob'
      bob.pet.name.should == 'ace'
      bob.pet.should == ana.pet
    end
  end
end
