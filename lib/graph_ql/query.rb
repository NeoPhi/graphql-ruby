class GraphQL::Query
  # If a resolve function returns `GraphQL::Query::DEFAULT_RESOLVE`,
  # The executor will send the field's name to the target object
  # and use the result.
  DEFAULT_RESOLVE = :__default_resolve
  attr_reader :schema, :document, :context, :fragments, :params

  # Prepare query `query_string` on {GraphQL::Schema} `schema`
  # @param schema [GraphQL::Schema]
  # @param query_string [String]
  # @param context [#[]] (default: `nil`) an arbitrary hash of values which you can access in {GraphQL::Field#resolve}
  # @param params [Hash] (default: `{}`) values for `$variables` in the query
  # @param debug [Boolean] (default: `true`) if true, errors are raised, if false, errors are put in the `errors` key
  # @param validate [Boolean] (default: `true`) if true, `query_string` will be validated with {StaticValidation::Validator}
  def initialize(schema, query_string, context: nil, params: {}, debug: true, validate: true)
    @schema = schema
    @debug = debug
    @query_string = query_string
    @context = Context.new(context)
    @params = params
    @validate = validate
    @fragments = {}
    @operations = {}

    @document = GraphQL.parse(@query_string)
    @document.parts.each do |part|
      if part.is_a?(GraphQL::Nodes::FragmentDefinition)
        @fragments[part.name] = part
      elsif part.is_a?(GraphQL::Nodes::OperationDefinition)
        @operations[part.name] = part
      end
    end
  end

  # Get the result for this query, executing it once
  def result
    if validation_errors.any?
      return { "errors" => validation_errors }
    end

    @result ||= {
      "data" => execute,
    }
  rescue StandardError => err
    if @debug
      raise err
    else
      message = "Something went wrong during query execution: #{err}" # \n  #{err.backtrace.join("\n  ")}"
      {"errors" => [{"message" => message}]}
    end
  end

  private

  def execute
    @operations.reduce({}) do |memo, (name, operation)|
      resolver = Projection::OperationProjector.new(operation, self)
      memo.merge(resolver.result)
    end
    @operations.reduce({}) do |memo, (name, operation)|
      resolver = OperationResolver.new(operation, self)
      memo.merge(resolver.result)
    end
  end

  def validation_errors
    @validation_errors ||= begin
      if @validate
        @schema.static_validator.validate(@document)
      else
        []
      end
    end
  end
end

require 'graph_ql/query/arguments'
require 'graph_ql/query/projection'
require 'graph_ql/query/context'
require 'graph_ql/query/field_resolution_strategy'
require 'graph_ql/query/fragment_spread_resolution_strategy'
require 'graph_ql/query/inline_fragment_resolution_strategy'
require 'graph_ql/query/operation_resolver'
require 'graph_ql/query/selection_resolver'
require 'graph_ql/query/type_resolver'
require 'graph_ql/query/directive_chain'
