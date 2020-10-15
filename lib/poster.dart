import 'dart:convert';
import 'dart:core';
import 'dart:math';

import 'package:mustache/mustache.dart';
import 'package:nyxx/nyxx.dart';
import 'package:postgres/postgres.dart';
import 'package:robocore/database.dart';
import 'package:robocore/robocore.dart';

class Field {
  late String label, content;
  Field(this.label, this.content);

  Map<String, dynamic> toJson() {
    return {"label": label, "content": content};
  }

  Field.fromJson(Map<String, dynamic> json) {
    label = json['label'];
    content = json['content'];
  }
}

class Poster {
  late String name;
  late Map<String, dynamic> reveal;
  late int channelId;

  late String title;
  String? thumbnailUrl;
  String? imageUrl;

  /// Time it ends
  late DateTime end;
  late DateTime revealEnd;

  /// Minutes
  late int updateInterval;
  late int recreateInterval;

  /// Last recreate and update
  DateTime recreated = DateTime(2000);
  DateTime updated = DateTime(2000);

  List<Field> fields = [];

  Snowflake messageId = Snowflake(0);

  Poster.fromJson(this.name, dynamic json) {
    end = DateTime.parse(json['end']);
    revealEnd = DateTime.parse(json['revealEnd']);
    recreateInterval = json['recreate'];
    updateInterval = json['update'];
    channelId = json['channelId'];
    _readContent(json['content']);
  }

  toJson() {
    Map<String, dynamic> json = {};
    json['end'] = end.toIso8601String();
    json['revealEnd'] = revealEnd.toIso8601String();
    json['recreate'] = recreateInterval;
    json['update'] = updateInterval;
    json['channelId'] = channelId;
    json['content'] = _writeContent();
    return json;
  }

  _readContent(Map json) {
    title = json['title'] ?? title;
    imageUrl = json['imageUrl'] ?? imageUrl;
    thumbnailUrl = json['thumbnailUrl'] ?? thumbnailUrl;
    reveal = json['reveal'] ?? reveal;
    var fs = json['fields'];
    if (fs != null) {
      fields = [];
      for (var field in fs) {
        addField(field['label'], field['content']);
      }
    }
  }

  _writeContent() {
    Map<String, dynamic> json = {};
    json['title'] = title;
    json['imageUrl'] = imageUrl;
    json['thumbnailUrl'] = thumbnailUrl;
    json['reveal'] = reveal;
    json['fields'] = <Map>[];
    var fs = json['fields'];
    if (fields.isNotEmpty) {
      for (var field in fields) {
        fs.add(field.toJson());
      }
    }
    return json;
  }

  addField(String label, content) {
    fields.add(Field(label, content));
  }

  static Future<PostgreSQLResult> dropTable() async {
    return await db.query("drop table if exists _poster;");
  }

  static Future<PostgreSQLResult> createTable() async {
    return await db.query(
        "create table IF NOT EXISTS _poster (name text NOT NULL PRIMARY KEY, info json NOT NULL);");
  }

  Future<void> insert() async {
    posters = null;
    await db.query("INSERT INTO _poster (name, info) VALUES (@name, @info)",
        substitutionValues: {"name": name, "info": toJson()});
  }

  Future<void> delete() async {
    // Invalidate cache
    posters = null;
    await db.query("DELETE FROM _poster where name = @name",
        substitutionValues: {"name": name});
  }

  static List<Poster>? posters;

  static Future<Poster?> find(String name) async {
    var ps = await getAll();
    return ps.firstWhere((p) => p.name == name);
  }

  static Future<List<Poster>> getAll() async {
    if (posters != null) return posters as List<Poster>;
    List<List<dynamic>> results =
        await db.query("SELECT name, info FROM _poster");
    posters = results
        .map((list) => Poster.fromJson(list.first, jsonDecode(list[1])))
        .toList();
    return posters as List<Poster>;
  }

  /// Create (and delete any existing) embed
  recreate(Robocore bot) async {
    deleteMessage(bot);
    var embed = build(bot);
    var channel = await bot.getChannel(channelId);
    // Send embed and store message id
    messageId = (await channel.send(embed: embed)).id;
    recreated = DateTime.now();
  }

  // Delete message
  deleteMessage(Robocore bot) async {
    if (messageId != 0)
      try {
        var channel = await bot.getChannel(channelId);
        var oldMessage = await channel.getMessage(messageId);
        if (oldMessage != null) {
          // Delete it
          await oldMessage.delete();
        }
      } catch (e) {
        log.warning("Failed deleting poster message: $messageId");
      }
  }

  /// Update content of existing embed
  update(Robocore bot) async {
    // If message exists
    // Find embed
    if (messageId != 0)
      try {
        var channel = await bot.getChannel(channelId);
        var oldMessage = await channel.getMessage(messageId);
        if (oldMessage == null) {
          log.warning("Oops, missing poster!");
          return;
        }
        var embed = build(bot);
        // Edit it
        oldMessage.edit(embed: embed);
        updated = DateTime.now();
      } catch (e) {
        log.warning("Failed updating poster message: $messageId");
      }
  }

  EmbedBuilder build(Robocore bot) {
    // Create embed
    var embed = EmbedBuilder();
    embed.title = title;
    if (thumbnailUrl != null) embed.thumbnailUrl = thumbnailUrl;
    if (imageUrl != null) embed.imageUrl = imageUrl;
    for (var f in fields) {
      var content = merge(f.content, bot);
      embed.addField(name: f.label, content: content);
    }
    //embed.timestamp = DateTime.now().toUtc();
    return embed;
  }

  String toString() => name;

  tick(Robocore bot) {
    print("tick");
    try {
      var now = DateTime.now();
      // Time to delete?
      if (revealEnd.isBefore(now)) {
        print("Delete");
        deleteMessage(bot);
        delete();
        return;
      }
      // Time to end and reveal?
      if (end.isBefore(now)) {
        print("Reveal");
        _readContent(reveal);
        return update(bot);
      }
      // Time to recreate?
      if (recreated.add(Duration(minutes: recreateInterval)).isBefore(now)) {
        print("Recreate");
        return recreate(bot);
      }
      // Time to update?
      if (updated.add(Duration(minutes: updateInterval)).isBefore(now)) {
        print("Update");
        return update(bot);
      }
    } catch (e) {
      log.warning("Failed tick of poster: $e");
    }
  }

  String merge(String template, Robocore bot) {
    var temp = Template(template,
        name: 'test', lenient: false, htmlEscapeValues: false);
    var now = DateTime.now();
    var left = end.difference(now);
    var daysLeft = left.inDays;
    left = left - Duration(days: daysLeft);
    var hoursLeft = left.inHours;
    left = left - Duration(hours: hoursLeft);
    var minutesLeft = left.inMinutes;
    var buf = StringBuffer();
    if (minutesLeft <= 0) {
      buf.write("now");
    } else {
      buf.write("in ");
      if (daysLeft > 0) {
        buf.write("$daysLeft days, ");
      }
      if (hoursLeft > 0) {
        buf.write("$hoursLeft hours, and ");
      }
      if (minutesLeft > 0) {
        buf.write("$minutesLeft minutes");
      }
    }
    var countDown = buf.toString();
    return temp.renderString({
      'countdown': countDown,
      'days': daysLeft,
      'hours': hoursLeft,
      'minutes': minutesLeft,
      'now': now.toIso8601String(),
      'price': bot.priceStringCORE()
    });
  }
}