import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:robocore/chat/robomessage.dart';
import 'package:robocore/database.dart';

class RoboUser {
  late int id;
  int? discordId, telegramId;
  DateTime created = DateTime.now().toUtc();

  RoboUser(this.id, this.discordId, this.telegramId, this.created);
  RoboUser.discord(this.discordId);
  RoboUser.telegram(this.telegramId);
  RoboUser.both(this.discordId, this.telegramId);

  RoboUser.fromDb(
      this.id, this.discordId, this.telegramId, this.created, dynamic json) {
    // Pick out stuff from json
    readJson(json);
  }

  writeJson() {
    Map<String, dynamic> json = {};
    // json['xxx'] = start.toIso8601String();
    return json;
  }

  bool isImpostor(RoboMessage msg) {
    return false; // TODO: Perform lookup and verify nick
  }

  readJson(Map json) {}

  @override
  bool operator ==(other) {
    if (other is RoboUser)
      return other.discordId == this.discordId ||
          other.telegramId == this.telegramId;
    return false;
  }

  static Future<PostgreSQLResult> dropTable() async {
    return await db.query("drop table if exists _robouser;");
  }

  static Future<PostgreSQLResult> createTable() async {
    return await db.query(
        "create table IF NOT EXISTS _robouser (id integer GENERATED ALWAYS AS IDENTITY, PRIMARY KEY(id), created timestamp, discordid integer, telegramid integer, info json NOT NULL);");
  }

  Future<void> update() async {
    await db.query(
        "UPDATE _robouser set created = @created, discordid = @discordid, telegramid = @telegramid, json = @json where id = @id",
        substitutionValues: {
          "id": id,
          "created": created.toIso8601String(),
          "discordid": discordId,
          "telegramid": telegramId,
          "json": writeJson()
        });
  }

  Future<void> insert() async {
    await db.query(
        "INSERT INTO _robouser (created, discordid, telegramid, info) VALUES (@created, @discordid, @telegramid, @info)",
        substitutionValues: {
          "created": created.toIso8601String(),
          "discordid": discordId,
          "telegramid": telegramId,
          "json": writeJson()
        });
  }

  static Future<RoboUser?> findUser({int? discordId, telegramId}) async {
    List<List<dynamic>> results;
    if (discordId != null) {
      results = await db.query(
          "SELECT id, created, discordId, telegramId, info  FROM _robouser where discordId = @discordId",
          substitutionValues: {"discordId": discordId});
    } else {
      results = await db.query(
          "SELECT id, created, discordId, telegramId, info  FROM _robouser where telegramId = @telegramId",
          substitutionValues: {"telegramId": telegramId});
    }
    if (results.isNotEmpty) {
      var list = results.first;
      return RoboUser.fromDb(
          list[0], list[1], list[2], list[3], jsonDecode(list[4]));
    }
  }

  static Future<RoboUser> findOrCreateUser({int? discordId, telegramId}) async {
    var user = await findUser(discordId: discordId, telegramId: telegramId);
    if (user == null) {
      // Then we create one
      user = RoboUser.both(discordId, telegramId);
      await user.insert();
      // Reload to get id
      user =
          await RoboUser.findUser(discordId: discordId, telegramId: telegramId);
    }
    return user as RoboUser;
  }

  static Future<List<RoboUser>> getAllUsers() async {
    List<List<dynamic>> results = await db.query(
        "SELECT id, created, discordId, telegramId, info  FROM _robouser");
    return results.map((list) {
      return RoboUser.fromDb(
          list[0], list[1], list[2], list[3], jsonDecode(list[4]));
    }).toList();
  }

  String toString() => "RoboUser($discordId, $telegramId)";
}
