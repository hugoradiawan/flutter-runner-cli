typedef Json = Map<String, dynamic>;

abstract class Model<M> {
  const Model();

  Json toJson();

  M? fromJson(dynamic json);
}
