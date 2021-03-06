import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:neat_periodic_task/neat_periodic_task.dart';
import 'package:nyxx/nyxx.dart';
import 'package:robocore/blocklytics.dart';
import 'package:robocore/chat/discordchannel.dart';
import 'package:robocore/chat/robochannel.dart';
import 'package:robocore/chat/robodiscord.dart';
import 'package:robocore/chat/robodiscordmessage.dart';
import 'package:robocore/chat/robofakemessage.dart';
import 'package:robocore/chat/robotelegram.dart';
import 'package:robocore/chat/robotelegrammessage.dart';
import 'package:robocore/model/robouser.dart';
import 'package:robocore/chat/telegramchannel.dart';
import 'package:robocore/commands/admincommand.dart';
import 'package:robocore/commands/command.dart';
import 'package:robocore/commands/faqcommand.dart';
import 'package:robocore/commands/helpcommand.dart';
import 'package:robocore/commands/idcommand.dart';
import 'package:robocore/commands/lgecommand.dart';
import 'package:robocore/commands/logcommand.dart';
import 'package:robocore/commands/mentioncommand.dart';
import 'package:robocore/commands/paircommand.dart';
import 'package:robocore/commands/postercommand.dart';
import 'package:robocore/commands/pricecommand.dart';
import 'package:robocore/commands/startcommand.dart';
import 'package:robocore/commands/statscommand.dart';
import 'package:robocore/commands/tllcommand.dart';
import 'package:robocore/ethclient.dart';
import 'package:robocore/loggers/eventlogger.dart';
import 'package:robocore/config.dart';
import 'package:robocore/ethereum.dart';
import 'package:robocore/model/swap.dart';
import 'package:robocore/uniswap.dart';
import 'package:robocore/util.dart';
import 'package:robocore/model/poster.dart';
import 'package:teledart/model.dart';
import 'package:teledart/teledart.dart';
import 'package:teledart/telegram.dart';

import 'database.dart';

// Super users
var gokr = RoboUser.both(124467899447508992, 1156133961);
var CryptoXman = RoboUser.both(298396371789152258, 1179513113);
var xRevert = RoboUser.both(751362716962390086, 1118664380);
var X3 = RoboUser.both(757109953910538341, 1358048057);

var priceDiscussionChannel = DiscordChannel(759890072392302592);
var priceAndTradingChat = TelegramChannel(-1001361865863);
var robocoreChannel = DiscordChannel(764120413507813417);
var robocoreDevelopmentChannel = DiscordChannel(763138788297408552);

// For tests
var robocoreTestGroup = TelegramChannel(-440184090);
var robocoreTestChannel = DiscordChannel(762629759393726464);
var robocoreTestChannelLogger = DiscordChannel(763910363439431700);

/// The bot
class Robocore {
  late Map config;
  late Nyxx nyxx;
  bool discordReady = false;
  late TeleDart teledart;
  bool teledartReady = false;

  /// Abstraction wrappers
  late RoboDiscord discord;
  late RoboTelegram telegram;

  // All loggers
  List<EventLogger> loggers = [];

  /// To interact with Ethereum contracts
  late EthClient ethClient;

  late StreamSubscription subscription;

  ClientUser get self => nyxx.self;

  /// Commands
  List<Command> commands = [];

  late num priceETHinUSD,
      priceWBTCinETH,
      priceWBTCinUSD,
      floorCOREinUSD,
      floorCOREinETH,
      floorLPinUSD,
      floorLPinETH,
      floorLP2inUSD,
      floorLP2inWBTC,
      floorLiquidity,
      floorLiquidity2,
      TLLinUSD,
      TVPLinUSD;

  Robocore(this.config);

  // Just testing stuff
  test() async {
    await openDatabase(config);
    log.info("Postgres opened: ${db.databaseName}");

    // Create our interface with Ethereum
    ethClient = EthClient.randomKey(config['apiurl'], config['wsurl']);
    await ethClient.initialize();

    // GraphQL wrappers
    await Blocklytics().connect(config['thegraph']);
    await Uniswap().connect(config['thegraph']);

    // Create our Ethereum world
    await Ethereum(ethClient).initialize();

    // One initial update
    await updatePriceInfo(null);
  }

  bool realRobo() {
    return config['prod'];
  }

  addLogger(EventLogger logger) {
    loggers.removeWhere((element) =>
        element.channel == logger.channel && element.name == logger.name);
    loggers.add(logger);
  }

  removeLogger(String name, RoboChannel ch) {
    loggers.removeWhere(
        (element) => element.channel == ch && element.name == name);
  }

  removeLoggers(RoboChannel ch) {
    loggers.removeWhere((element) => element.channel == ch);
  }

  loggersFor(RoboChannel ch) {
    return loggers.where((element) => element.channel == ch).toList();
  }

  /// Run contract queries
  background() async {
    // Update pair stats
    try {
      await ethereum.fetchStats();
    } catch (e, s) {
      log.warning("Exception during update of pair stats $e, $s", e, s);
    }
    // Update posters
    try {
      var posters = await Poster.getAll();
      for (var p in posters) {
        // Call for both Discord and Telegram
        p.update(discord);
        p.update(telegram);
      }
    } catch (e, s) {
      log.warning("Exception during update of posters", e, s);
    }
  }

  Future<ITextChannel> getDiscordChannel(int id) async {
    return await nyxx.getChannel<ITextChannel>(Snowflake(id.toString()));
  }

  Future<Chat> getTelegramChat(int id) async {
    return await teledart.telegram.getChat(id);
  }

  Future<double> getFot() async {
    final result =
        await ethereum.TRANSFERCHECKER.callFunction('feePercentX100');
    return result.first.toDouble() / 10.0;
  }

/*
  updateLGE2Info() async {
    //lge2CORE = raw18(await core.lge2TotalCOREContributed());
    //lge2COREinUSD = lge2CORE * priceCOREinUSD;
    //lge2ETH = raw18(await core.lge2TotalETHContributed());
    //lge2ETHinUSD = lge2ETH * priceETHinUSD;
    //lge2WrapToken = raw18(await core.lge2TotalWrapTokenContributed());
    lge2COREBought = raw18(await CoreBought.getTotalSum());
    lge2COREBoughtInUSD = lge2COREBought * priceCOREinUSD;
    lge2COREBoughtLast24Hours =
        raw18(await CoreBought.getSumLast(Duration(hours: 24)));
    lge2COREBoughtLast24HoursInUSD = lge2COREBoughtLast24Hours * priceCOREinUSD;

    lge2ETHContributedLastHour =
        raw18(await Contribution.getSumLast(Duration(hours: 1)));
    lge2ETHContributedLastHourInUSD =
        lge2ETHContributedLastHour * priceCOREinUSD;

    lge2CORE = raw18(
        await ethClient.balanceOf(ethClient.ethClient, ethClient.LGE2Addr));
    lge2COREinUSD = lge2CORE * priceCOREinUSD;
    lge2WBTC =
        raw8(await ethClient.balanceOf(ethClient.wbtc, ethClient.LGE2Addr));
    lge2WBTCinUSD = lge2WBTC * priceWBTCinUSD;
  }
*/
  // Update base metrics to get ETH and WBTC in USD.
  updateBaseMetrics() async {
    var reserves = await ethereum.ETH2USDT.getReserves();
    priceETHinUSD = raw6(reserves[1]) / raw18(reserves[0]);
    reserves = await ethereum.WBTC2ETH.getReserves();
    priceWBTCinETH = raw18(reserves[1]) / raw8(reserves[0]);
    priceWBTCinUSD = priceWBTCinETH * priceETHinUSD;
    //reserves = await ethereum.WBTC2USDT.getReserves();
    //priceWBTCinUSD = raw6(reserves[1]) / raw8(reserves[0]);
  }

  /// Update base metrics (USD prices), the affected pair and finally floor of CORE.
  updatePriceInfo(Swap? swap) async {
    await updateBaseMetrics();
    if (swap != null) {
      swap.pair.update();
    } else {
      ethereum.CORE2ETH.update();
      ethereum.CORE2CBTC.update();
    }
    updateFloorPrice();
  }

  // Update Floor price of CORE, in ETH.
  updateFloorPrice() async {
    // Selling CORE2ETH back into pair1 and the rest into pair2:
    //
    // var newPoolETH = poolK / (poolCORE + (CORE2ETH * 0.997));
    // var newPoolWBTC = poolK2 / (poolCORE2 + (10000 - poolCORE2 - poolCORE - CORE2ETH) * 0.997);

    // Then price should be equal afterwards:
    // var price1 = newPoolETH / (poolCORE + CORE2ETH)
    // var price2 = (newPoolWBTC / (10000 - poolCORE - CORE2ETH)) * priceBTCinETH

    // So we want to know CORE2ETH:
    // newPoolETH / (poolCORE + CORE2ETH) = (newPoolWBTC / (10000 - poolCORE - CORE2ETH)) * priceBTCinETH
    //
    // Expanding one more step:
    // (poolK / (poolCORE + (CORE2ETH) * 0.997)) / (poolCORE + CORE2ETH) = (poolK2 / (poolCORE2 + (10000 - poolCORE2 - poolCORE - CORE2ETH) * 0.997)) / (10000 - poolCORE - CORE2ETH) * priceBTCinETH
    //
    // And replacing with single letter variables (to make Symbolab happy):
    // (k / (c + (x * 0.997))) / (c + x) = (l / (d + (10000 - d - c - x) * 0.997)) / (10000 - c - x) * z
    var p1 = ethereum.CORE2ETH;
    var p2 = ethereum.CORE2CBTC;
    var pool1CORE = p1.pool1;
    var pool2CORE = p2.pool1;
    var c = pool1CORE;
    var k = p1.poolK;
    var l = p2.poolK;
    var z = priceWBTCinUSD / priceETHinUSD; // priceBTCinETH
    var d = p2.pool1;
    // The following was figured out using:
    // https://www.symbolab.com/solver/equation-calculator/solve%20for%20x%2C%20%5Cleft(k%20%2F%20%5Cleft(c%20%2B%20x%20%5Ccdot%200.997%5Cright)%5Cright)%20%2F%20%5Cleft(c%20%2B%20x%5Cright)%20%3D%20%5Cleft(l%20%2F%20%5Cleft(d%20%2B%20%5Cleft(10000%20-%20d%20-%20c%20-%20x%5Cright)%20%5Ccdot%200.997%5Cright)%5Cright)%20%5Ccdot%20z%2F%20%5Cleft(10000%20-%20c%20-%20x%5Cright)
    var zz = 0.000009 * pow(c, 2) * pow(l, 2) * pow(z, 2) +
        0.000018 * c * l * d * k * z +
        119.64 * c * l * k * z +
        119.64 * l * d * k * z +
        397603600 * l * k * z +
        0.000009 * pow(d, 2) * pow(k, 2);
    var temp1 = (2 * (0.997 * k - 0.997 * l * z));
    var temp2 = -1.994 * c * k + 0.003 * d * k + 19940 * k + 1.997 * c * l * z;
    var x1 = (temp2 + sqrt(zz)) / temp1;
    var x2 = (temp2 - sqrt(zz)) / temp1;
    print("Solutions x1: $x1, x2: $x2");

    // So now we have x1 and x2, two possible solutions to amount of CORE to sell into pair1
    // either using CORE from outside or from pair2. Now we need to see which one
    // gives lowest price.
    double candidate = double.maxFinite;
    var newPoolWBTC, newPoolETH;
    if (x1 < (10000 - pool1CORE)) {
      // x1 needs to be less than available CORE
      newPoolETH = k / (pool1CORE + (x1 * 0.997));
      var p1 = newPoolETH / (pool1CORE + x1);
      print("poolK: $k, newPoolK: ${newPoolETH * (pool1CORE + x1)}");
      newPoolWBTC = l / (d + (10000 - d - pool1CORE - x1) * 0.997);
      var p2 = (newPoolWBTC / (10000 - pool1CORE - x1)) * z;
      print("poolK2: $l, newPoolK2: ${newPoolWBTC * (10000 - pool1CORE - x1)}");
      print("pool1CORE: ${pool1CORE + x1}, pool1ETH: $newPoolETH");
      print("pool2CORE: ${10000 - pool1CORE - x1}, pool2WBTC: $newPoolWBTC");
      print("Price 1 of CORE-ETH: $p1, CORE-WBTC: $p2");
      candidate = p1;
    }
    if (x2 < (10000 - pool1CORE)) {
      // x2 needs to be low enough
      var newPoolETH2 = k / (pool1CORE + (x2 * 0.997));
      var p1 = newPoolETH2 / (pool1CORE + x2);
      print("poolK: $k, newPoolK: ${newPoolETH2 * (pool1CORE + x2)}");
      var newPoolWBTC2 = l / (d + (10000 - d - pool1CORE - x2) * 0.997);
      var p2 = (newPoolWBTC2 / (10000 - pool1CORE - x2)) * z;
      print("poolK2: $l, newPoolK: ${newPoolWBTC2 * (10000 - pool1CORE - x2)}");
      print("pool1CORE: ${pool1CORE + x2}, pool1ETH: $newPoolETH2");
      print("pool2CORE: ${10000 - pool1CORE - x2}, pool2WBTC: $newPoolWBTC2");
      print("Price 2 of CORE-ETH: $p1, CORE-WBTC: $p2");
      // Was this the less?
      if (p1 < candidate) {
        newPoolWBTC = newPoolWBTC2;
        newPoolETH = newPoolETH2;
        candidate = p1;
      }
    }
    floorCOREinETH = candidate;
    floorCOREinUSD = floorCOREinETH * priceETHinUSD;

    // And then we can also calculate floor of LPs
    // The liquidity is simply twice newPoolXXX
    floorLiquidity = newPoolETH * 2;
    floorLPinETH = floorLiquidity / p1.supplyLP;
    floorLPinUSD = floorLPinETH * priceETHinUSD;
    floorLiquidity2 = newPoolWBTC * 2;
    floorLP2inWBTC = floorLiquidity2 / p2.supplyLP;
    floorLP2inUSD = floorLP2inWBTC * priceWBTCinUSD;

    // TLL - Total Liquidity Locked
    TLLinUSD = ethereum.CORE2CBTC.liquidity * priceWBTCinUSD;
    TLLinUSD += ethereum.CORE2ETH.liquidity * priceETHinUSD;
    // TVPL - Total Value Permanently Locked
    TVPLinUSD = floorLiquidity * priceETHinUSD;
    TVPLinUSD += floorLiquidity2 * priceWBTCinUSD;

    // Calculating floor and TLL/TVPL using q
    //var q = (10000 - )
  }

  // Shortcuts for readability
  num get priceCOREinETH => ethereum.CORE2ETH.price1;
  num get priceCOREinCBTC => ethereum.CORE2CBTC.price1;
  num get priceETHinCORE => ethereum.CORE2ETH.price2;
  num get priceCBTCinCORE => ethereum.CORE2CBTC.price2;
  num get priceCOREinUSD => priceCOREinETH * priceETHinUSD;
  num get valueLPinETH => ethereum.CORE2ETH.valueLP;
  num get valueLPinUSD => valueLPinETH * priceETHinUSD;
  num get priceLPinETH => ethereum.CORE2ETH.priceLP;
  num get priceLPinUSD => priceLPinETH * priceETHinUSD;
  num get valueLP2inCBTC => ethereum.CORE2CBTC.valueLP;
  num get valueLP2inUSD => valueLP2inCBTC * priceWBTCinUSD;
  num get priceLP2inETH => ethereum.CORE2CBTC.priceLP;
  num get priceLP2inUSD => priceLP2inETH * priceETHinUSD;

  String priceStringCORE([num amount = 1]) {
    return "$amount CORE = ${usd2(priceCOREinUSD * amount)} (${dec4(priceCOREinETH * amount)} ETH)";
  }

  String floorStringCORE([num amount = 1]) {
    return "$amount FLOOR CORE = ${usd2(floorCOREinUSD * amount)} (${dec4(floorCOREinETH * amount)} ETH)";
  }

  String floorStringLP1([num amount = 1]) {
    return "$amount FLOOR LP = ${usd2(floorLPinUSD * amount)} (${dec4(floorLPinETH * amount)} ETH)";
  }

  String floorStringLP2([num amount = 1]) {
    return "$amount FLOOR cmLP = ${usd2(floorLP2inUSD * toCentimilli(amount))} (${dec4(floorLP2inWBTC * toCentimilli(amount))} CBTC)";
  }

  String priceStringLP1([num amount = 1]) {
    return "$amount LP = ${usd2(priceLPinUSD * amount)} (${dec4(priceLPinETH * amount)} ETH)";
  }

  String valueStringLP1([num amount = 1]) {
    return "$amount LP = ${usd2(valueLPinUSD * amount)} (${dec4(valueLPinETH * amount)} ETH)";
  }

  String priceStringLP2([num amount = 1]) {
    return "$amount cmLP = ${usd2(priceLP2inUSD * toCentimilli(amount))} (${dec4(priceLP2inETH * toCentimilli(amount))} ETH)";
  }

  String valueStringLP2([num amount = 1]) {
    return "$amount cmLP = ${usd2(valueLP2inUSD * toCentimilli(amount))} (${dec4(valueLP2inCBTC * toCentimilli(amount))} CBTC)";
  }

  String priceStringETH([num amount = 1]) {
    return "$amount ETH = ${usd2(priceETHinUSD * amount)} (${dec4(priceETHinCORE * amount)} CORE)";
  }

  String priceStringWBTC([num amount = 1]) {
    return "$amount WBTC = ${usd2(priceWBTCinUSD * amount)} (${dec4(priceCBTCinCORE * amount)} CORE)";
  }

  updateUsername() async {
    /*if (ready) {
      await discord.self
          .edit(username: "RoboCORE", avatar: File("www/robo.png"));
      try {
        print("Getting guild");
        var guild = await bot.getGuild(Snowflake("759889689409749052"));
        print("Got guild! $guild");
        guild.changeSelfNick("RoboCORE ${usd0(priceCOREinUSD)}");
      } catch (e) {
        print(e);
      }
    }
  */
  }

  buildCommands() {
    commands
      ..add(MentionCommand())
      ..add(HelpCommand())
      ..add(FAQCommand())
      ..add(StartCommand())
      ..add(StatsCommand())
      ..add(LGECommand())
      ..add(LogCommand()
        ..validForAllInDM = true
        ..users = [gokr, CryptoXman, xRevert, X3]
        ..whitelist = [
          priceAndTradingChat,
          priceDiscussionChannel,
          robocoreTestGroup,
          robocoreChannel,
          robocoreDevelopmentChannel
        ])
      ..add(PriceCommand())
      ..add(PairCommand())
      ..add(TLLCommand())
      ..add(IdCommand())
      ..add(AdminCommand()..users = [gokr])
      ..add(PosterCommand()..users = [gokr, CryptoXman, xRevert, X3]);
  }

  /// Go through all loggers and let them log if they want to
  performLogging(Swap swap) {
    for (var logger in loggers) {
      try {
        logger.log(this, swap);
      } catch (e) {
        log.warning("Error calling logger: $e");
      }
    }
  }

  start() async {
    await openDatabase(config);
    log.info("Postgres opened: ${db.databaseName}");

    // Create our two bots
    nyxx = Nyxx(config['nyxx'], useDefaultLogger: false);
    teledart = TeleDart(Telegram(config['teledart']), Event());

    // Create abstraction wrappers
    discord = RoboDiscord(this);
    telegram = RoboTelegram(this);

    // GraphQL wrappers
    await Blocklytics().connect(config['thegraph']);
    await Uniswap().connect(config['thegraph']);

    // Create our interface with Ethereum
    ethClient = EthClient.randomKey(config['apiurl'], config['wsurl']);
    await ethClient.initialize();

    // Create our Ethereum world
    await Ethereum(ethClient).initialize();

    // Add all commands
    buildCommands();

    // Standard setup, if I am real RoboCORE
    if (realRobo()) {
      print("This is prod, performing standard setup");
      for (var cmd in [
        "!l add core-eth price 5",
        "!l add core-cbtc price 5",
        "!l add core-eth whalebuy 10",
        "!l add core-cbtc whalebuy 10"
      ]) {
        RoboFakeMessage(this, cmd, priceAndTradingChat, gokr).runCommands();
      }
      for (var cmd in [
        "!l add core-eth price 5",
        "!l add core-cbtc price 5",
        "!l add core-eth whalebuy 10",
        "!l add core-cbtc whalebuy 10",
        "!l add core-eth whalesell 10",
        "!l add core-cbtc whalesell 10"
      ]) {
        RoboFakeMessage(this, cmd, priceDiscussionChannel, gokr).runCommands();
      }
    } else {
      print("This is NOT prod");
    }

    // One initial update
    await updatePriceInfo(null);

    // We listen to all Swaps on COREETH
    subscription = ethereum.CORE2ETH.listenToEvent('Swap', (ev, event) {
      //print("Topics: ${event.topics} data: ${event.data}");
      try {
        var swap = Swap.from(ev, event, ethereum.CORE2ETH);
        updatePriceInfo(swap);
        performLogging(swap);
      } catch (e) {
        log.warning("Exception during swap handling: ${e.toString()}");
      }
    });

    // We listen to all Swaps on CORE2CBTC
    subscription = ethereum.CORE2CBTC.listenToEvent('Swap', (ev, event) {
      //print("Topics: ${event.topics} data: ${event.data}");
      try {
        var swap = Swap.from(ev, event, ethereum.CORE2CBTC);
        updatePriceInfo(swap);
        performLogging(swap);
      } catch (e) {
        log.warning("Exception during swap handling: ${e.toString()}");
      }
    });

    // When we are ready in Discord
    nyxx.onReady.listen((ReadyEvent e) async {
      log.info("Robocore in Discord is ready!");
      discordReady = true;
      await updateUsername();
    });

    // All Discord messages
    nyxx.onMessageReceived.listen((MessageReceivedEvent event) async {
      try {
        RoboDiscordMessage(this, event).runCommands();
      } catch (e) {
        log.warning("Exception during runcommands: ${e.toString()}");
      }
    });

    // When we are ready in Telegram
    teledart.start().then((me) {
      log.info('RoboCORE in Telegram is ready!');
      teledartReady = true;
    });

    // All Telegram bot commands
    teledart
        .onMessage(entityType: 'bot_command')
        .listen((TeleDartMessage message) async {
      try {
        RoboTelegramMessage(this, message).runCommands();
      } catch (e) {
        log.warning("Exception during runcommands: ${e.toString()}");
      }
    });

    // All Telegram messages mentioning me
    teledart
        .onMessage(entityType: 'mention')
        .listen((TeleDartMessage message) async {
      try {
        RoboTelegramMessage(this, message).runCommands();
      } catch (e) {
        log.warning("Exception during runcommands: ${e.toString()}");
      }
    });

    /* NOT YET!
    teledart.onInlineQuery().listen((inlineQuery) async {
      var query = inlineQuery.query;
      print("Query: $query");
      for (var cmd in commands) {
        var result = await cmd.inlineTelegram(query, this);
        if (result != null) {
          inlineQuery.answer([
            InlineQueryResultArticle()
              ..id = cmd.command
              ..title = result
              ..input_message_content = (InputTextMessageContent()
                ..message_text = result
                ..parse_mode = 'HTML')
          ]);
        }
      }
      inlineQuery.answer([
        InlineQueryResultArticle()
          ..id = 'noidea'
          ..title = 'No idea!'
          ..input_message_content = (InputTextMessageContent()
            ..message_text = 'Sorry, did not understand that!'
            ..parse_mode = 'HTML')
      ]);
    });
    */

    // Base background tasks are run every 10 seconds
    final scheduler = NeatPeriodicTaskScheduler(
      interval: Duration(seconds: 10),
      name: 'background',
      timeout: Duration(seconds: 60),
      task: () async => background(),
      minCycle: Duration(seconds: 5),
    );

    scheduler.start();
    await ProcessSignal.sigterm.watch().first;
    await scheduler.stop();
  }
}
