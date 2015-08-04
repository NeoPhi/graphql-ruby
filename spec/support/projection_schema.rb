# Project an incrementing integer
# Then resolve to display that integer
ProjectFromContextField = GraphQL::Field.new do |f, type, field, arg|
  f.type(!type.Int)
  f.description("Project the next integer")
  f.project -> (type, args, ctx)  { ctx[:counter] += 1 }
  f.resolve -> (obj, args, ctx) { GraphQL::Query::DEFAULT_RESOLVE }
end

ProjectorField = GraphQL::Field.new do |f, type, field|
  f.type(-> { ProjectorType })
  f.description("Return a Projector")
  f.resolve -> (object, arg, ctx) {
    values = ctx.projections.merge({name: "Projector #{ctx[:counter]}", resolvedInt: ctx[:counter] += 1 })
    OpenStruct.new(values)
  }
end


ProjectorType = GraphQL::ObjectType.new do |t, type, field|
  t.name("Projector")
  t.fields({
    projectedInt: ProjectFromContextField,
    projectedInt2: ProjectFromContextField,
    resolvedInt: field.build(type: !type.Int),
    projector: ProjectorField,
    name: field.build(type: !type.String),
  })
end

ProjectorQueryType = GraphQL::ObjectType.new do |t, type, field|
  t.fields({
    projector: ProjectorField,
  })
end

ProjectorSchema = GraphQL::Schema.new(query: ProjectorQueryType)
