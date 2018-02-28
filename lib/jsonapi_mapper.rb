require "jsonapi_mapper/version"

module JsonapiMapper
  def self.doc(document, rules, renames = {})
    DocumentMapper.new(document, [], rules, renames)
  end

  def self.doc_unsafe!(document, unscoped, rules, renames = {})
    DocumentMapper.new(document, unscoped, rules, renames)
  end

  class RulesError < StandardError; end;

  Id = Struct.new(:type, :raw)
  Type = Struct.new(:name, :class, :rule)
  Resource = Struct.new(:object, :relationships, :id)
  Rule = Struct.new(:attributes, :scope)

  class DocumentMapper
    attr_accessor :document, :unscoped, :types, :renames, :resources,
      :included, :data

    def initialize(document, unscoped, rules, renames)
      self.document = document.deep_symbolize_keys
      self.renames = renames.deep_symbolize_keys
      self.unscoped = unscoped.map(&:to_sym)
      self.resources = {}
      setup_types(rules)
      
      main = if data = self.document[:data]
        if data.is_a?(Array)
          data.map{|r| build_resource(r) }.compact.collect(&:object)
        else
          build_resource(data).try(:object)
        end
      end

      rest = if included = self.document[:included]
        included.map{|r| build_resource(r) }.compact
      end

      resources.each{|_,r| assign_relationships(r) }

      self.data = main
      self.included = rest.try(:map, &:object) || []
    end

    def setup_types(rules)
      self.types = {}
      rules.each do |type_name, ruleset|
        type_name = type_name.to_sym

        attrs, scope = if ruleset.last.is_a?(Hash)
          [ruleset[0..-2], ruleset.last]
        else
          unless unscoped.map(&:to_sym).include?(type_name)
            raise RulesError.new("Missing Scope for #{type_name}")
          end
          [ruleset, {}]
        end

        unless attrs.all?{|v| v.is_a?(Symbol) || v.is_a?(String) } 
          raise RulesError.new('Attributes must be Strings or Symbols')
        end

        attrs = attrs.map(&:to_sym)
        scope.symbolize_keys!

        danger = scope.keys.to_set & attrs.map{|a| renamed_attr(type_name, a) }.to_set
        if danger.count > 0
          raise RulesError.new("Don't let user set the scope: #{danger.to_a}")
        end

        cls = renamed_type(type_name)

        attrs.map{|a| renamed_attr(type_name, a) }.each do |attr|
          unless cls.new.respond_to?(attr)
            raise NoMethodError.new("undefined method #{attr} for #{cls}")
          end
        end

        types[type_name] = Type.new(type_name, cls, Rule.new(attrs, scope))
      end
    end

    def build_resource(json)
      return unless json.is_a? Hash
      return unless json.fetch(:relationships, {}).is_a?(Hash)
      return unless json.fetch(:attributes, {}).is_a?(Hash)
      return unless type = types[json[:type].try(:to_sym)]

      object = if json[:id].nil? || json[:id].to_s.starts_with?("@")
        type.class.new.tap do |o|
          type.rule.scope.each do |k,v|
            o.send("#{k}=", v)
          end
        end
      else
        type.class.where(type.rule.scope).find(json[:id])
      end

      relationships = {}
      json.fetch(:relationships, {}).each do |name, value|
        next unless type.rule.attributes.include?(name)
        next if value[:data].blank?
        relationships[renamed_attr(type.name, name)] = if value[:data].is_a?(Array)
          value[:data].map{|v| build_id(v) } 
        else
          build_id(value[:data])
        end
      end

      if new_values = json[:attributes]
        type.rule.attributes.each do |name|
          next unless new_values.has_key?(name)
          object.send("#{renamed_attr(type.name, name)}=", new_values[name]) 
        end
      end

      resource = Resource.new(object, relationships, build_id(json))
      resources[resource.id] = resource
    end

    def build_id(json)
      Id.new(json[:type].to_sym, json[:id])
    end

    def assign_relationships(resource)
      resource.relationships.each do |name, ids|
        if ids.is_a?(Array)
          ids.each do |id|
            next unless other = find_resource_object(id)
            resource.object.send(name).push(other)
          end
        else
          next unless other = find_resource_object(ids)
          resource.object.send("#{name}=", other)
        end
      end
    end

    def find_resource_object(id)
      return unless type = types[id.type]

      resources[id].try(:object) ||
        type.class.where(type.rule.scope).find(id.raw) or
        raise ActiveRecord::RecordNotFound
          .new("Couldn't find #{id.type} with id=#{id.raw}")
    end

    def renamed_type(type_name)
      renames.fetch(:types, {})[type_name] ||
        type_name.to_s.singularize.camelize.constantize
    end

    def unrenamed_type(type)
      type_name = type.to_s.underscore.pluralize
      renames.fetch(:types, {}).find{|k,v| v == type }.try(:first) || type_name
    end

    def renamed_attr(type, attr)
      renames.fetch(:attributes, {}).fetch(type, {}).fetch(attr, attr)
    end

    def unrenamed_attr(type_name, attr)
      renames.fetch(:attributes, {}).fetch(type_name, {})
        .find{|k,v| v == attr }.try(:first) || attr
    end

    def all
      (data_mappable + included)
    end

    def save_all
      return false unless all.all?(&:valid?)
      all.each(&:save)
      true
    end

    def all_valid?
      all.map(&:valid?).all? # This does not short-circuit, to get all errors.
    end

    def collection?
      data.is_a?(Array)
    end

    def single?
      !collection?
    end

    def map_data(cls, &blk)
      data_mappable.select{|o| o.is_a?(cls)}.map(&blk)
    end

    def map_all(cls, &blk)
      all.select{|o| o.is_a?(cls)}.map(&blk)
    end

    def data_mappable
      collection? ? data : [data].compact
    end

    def all_errors
      errors = []

      if collection?
        data.each_with_index do |resource, i|
          errors << serialize_errors_for("/data/#{i}", resource)
        end
      else
        errors << serialize_errors_for("/data", data)
      end
      
      included.each_with_index do |resource, i|
        errors << serialize_errors_for("/included/#{i}", resource)
      end

      { errors: errors.flatten.compact }
    end

    private

    def serialize_errors_for(prefix, model)
      return if model.errors.empty?
      model.errors.collect do |attr, value|
        type_name = unrenamed_type(model.class)
        meta = { type: type_name.to_s }
        meta[:id] = model.id if model.id
        {
          status: 422,
          title: value,
          detail: value,
          code: value.parameterize.underscore,
          meta: meta,
          source: {
            pointer: "#{prefix}/attributes/#{unrenamed_attr(type_name, attr)}"
          }
        }
      end
    end
  end
end
