module GraphQL::Query::Projection
  class OperationProjector
    attr_reader :definition, :query, :root
    def initialize(definition, query)
      @query = query
      @definition = definition
      @root = if definition.operation_type == "query"
        query.schema.query
      elsif definition.operation_type == "mutation"
        query.schema.mutation
      end
    end

    def result
      SelectionProjector.new(root, definition.selections, query).result
    end
  end

  class SelectionProjector
    PROJECTION_STRATEGIES = {
      GraphQL::Nodes::Field =>          :FieldProjectionStrategy,
      GraphQL::Nodes::FragmentSpread => :FragmentSpreadProjectionStrategy,
      GraphQL::Nodes::InlineFragment => :InlineFragmentProjectionStrategy,
    }

    attr_reader :type, :selections, :query
    def initialize(type, selections, query)
      @type = type.kind.unwrap(type)
      @selections = selections
      @query = query
    end

    def result
      return {} if selections.none?
      if !type.kind.fields?
        raise("Can't project on #{type.kind} because it doesnt have fields")
      end

      selections.reduce({}) do |memo, ast_field|
        chain = GraphQL::Query::DirectiveChain.new(ast_field, query) {
          strategy_class = GraphQL::Query::Projection.const_get(PROJECTION_STRATEGIES[ast_field.class])
          strategy = strategy_class.new(type, ast_field, query)
          strategy.result
        }
        memo.merge(chain.result)
      end
    end
  end

  class FieldProjectionStrategy
    attr_reader :result
    def initialize(type, ast_field, query)
      field_defn = type.fields[ast_field.name]
      child_projector = SelectionProjector.new(field_defn.type, ast_field.selections, query)
      child_projections = child_projector.result
      arguments = GraphQL::Query::Arguments.new(ast_field.arguments, field_defn.arguments, query.params).to_h
      query.context.projection_map[ast_field] = child_projections
      if field_defn.projects?
        projection = nil
        query.context.projecting(child_projections) do
          projection = field_defn.project(type, arguments, query.context)
        end
        field_label = ast_field.alias || ast_field.name
        @result = { field_label => projection }
      else
        @result = {}
      end
    end
  end

  class FragmentSpreadProjectionStrategy
    attr_reader :result
    def initialize(type, ast_fragment_spread, query)
      fragment_def = query.fragments[ast_fragment_spread.name]
      selections = fragment_def.selections
      resolver = GraphQL::Query::Projection::SelectionProjector.new(type, selections, query)
      @result = resolver.result
    end
  end

  class InlineFragmentProjectionStrategy
    attr_reader :result
    def initialize(type, ast_inline_fragment, query)
      selections = ast_inline_fragment.selections
      resolver = GraphQL::Query::Projection::SelectionProjector.new(type, selections, query)
      @result = resolver.result
    end
  end
end
