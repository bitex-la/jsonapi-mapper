require "jsonapi_mapper/version"

module JsonapiMapper
  def self.doc(document, rules)
    DocumentMapper.new(document, rules)
  end

  JsonId = Struct.new(:type, :id)
  Resource = Struct.new(:object, :json, :json_id)
  Rule = Struct.new(:attributes, :scope)

  class DocumentMapper
    attr_accessor :document, :rules, :classes, :resources, :data, :included

    def initialize(document, raw_rules)
      self.document = document.deep_symbolize_keys
      self.resources = {}
      self.classes = {}
      self.rules = {}

      raw_rules.each do |k,v|
        raise "Missing Scope for #{k}" unless v.last.is_a?(Hash)

        attrs = v[0..-2]

        unless attrs.all?{|v| v.is_a?(Symbol) || v.is_a?(String) } 
          raise 'Attributes must be Strings or Symbols'
        end

        cls = "#{k.to_s.singularize}".camelize.constantize
        attrs.each do |a|
          unless cls.new.respond_to?(a)
            raise NoMethodError.new("undefined method #{a} for #{cls}")
          end
        end

        rule = rules[k.to_sym] = Rule.new(attrs.map(&:to_sym), v.last)
        classes[k.to_sym] = [cls, rule]
      end

      main = build_resource(document[:data])
      rest = if included = document[:included]
        included.map{|r| build_resource(r) }.compact
      end

      resources.each do |k,v|
        build_relationships(v)
      end

      self.data = main.is_a?(Array) ? main.map(&:object) : main.object 
      self.included = rest.try(:map, &:object)
    end

    def save_all
      data.is_a?(Array) ? data.each(&:save) : data.save
      included.try(:each, &:save)
    end

    def collection?
      data.is_a?(Array)
    end

    # TODO: Save relationships in resource already as pointers.
    # TODO: Try to stop using json ever again after this lookup is done.
    def build_resource(json)
      return unless (cls, rule = classes[json[:type].to_sym])

      object = if json[:id].nil? || json[:id].to_s.starts_with?("@")
        cls.new.tap do |o|
          rule.scope.each do |k,v|
            o.send("#{k}=", v)
          end
        end
      else
        cls.where(rule.scope).find(json[:id])
      end

      if attrs = json[:attributes]
        rule.attributes.each do |name|
          if value = attrs[name]
            object.send("#{name}=", value) 
          end
        end
      end

      resource = Resource.new(object, json, build_json_id(json))
      resources[resource.json_id] = resource
      resource
    end

    # Building relationshisps depends on all resources to have been
    # previously created and registered in the self.resources hash.
    # TODO: Findind in resources should always raise.
    def build_relationships(resource)
      return unless relationships = resource.json[:relationships]
      relationships.each do |name, value|
        next unless rules[resource.json_id.type][:attributes].include?(name)
        if value[:data].is_a?(Array)
          value[:data].each do |v|
            if other = find_resource_object(build_json_id(v))
              resource.object.send(name).push(other)
            end
          end
        else
          if other = find_resource_object(build_json_id(value[:data]))
            resource.object.send("#{name}=", other)
          end
        end
      end
    end

    def build_json_id(json)
      JsonId.new(json[:type].to_sym, json[:id])
    end

    def find_resource_object(json_id)
      return unless (cls, rule = classes[json_id.type])

      resources[json_id].try(:object) ||
        cls.where(rule.scope).find(json_id.id) or
        raise ActiveRecord::RecordNotFound
          .new("Couldn't find #{json_id.type} with id=#{json_id.id}")
    end
  end
end
