import 'dart:math';

import 'package:robocore/contract.dart';

import 'package:robocore/ethclient.dart';

class Pair extends Contract {
  int id;
  String name;
  // Best would be to have both Tokens here too
  //Token t1;
  //Token t2;
  // We can pull these from ERC20Detailed.json later
  late int _decimals1;
  late BigInt pow1;
  late int _decimals2;
  late BigInt pow2;
  late int _decimalsLP;
  late BigInt powLP;

  set decimals1(int x) {
    _decimals1 = x;
    pow1 = BigInt.from(pow(10, _decimals1));
  }

  set decimals2(int x) {
    _decimals2 = x;
    pow2 = BigInt.from(pow(10, _decimals2));
  }

  set decimalsLP(int x) {
    _decimalsLP = x;
    powLP = BigInt.from(pow(10, _decimalsLP));
  }

  // These are all calculated when update() is called
  late num pool1, pool2, poolK;
  late num price1, price2, priceLP;
  late num supplyLP;

  num get liquidity => pool2 * 2;

  Pair(this.id, EthClient client, this.name, String addressHex)
      : super(client, 'UniswapPair.json', addressHex) {
    decimals1 = 18;
    decimals2 = 18;
    decimalsLP = 18;
  }

  initialize() async {
    await super.initialize();
    await update();
  }

  Future<List<dynamic>> getReserves() async {
    return await callFunction('getReserves');
  }

  Future<BigInt> totalSupply() async {
    final result = await callFunction('totalSupply');
    return result.first;
  }

  num raw1(BigInt amount) {
    return (amount / pow1).toDouble();
  }

  num raw2(BigInt amount) {
    return (amount / pow2).toDouble();
  }

  num rawLP(BigInt amount) {
    return (amount / powLP).toDouble();
  }

  update() async {
    var reserves = await getReserves();
    pool1 = raw1(reserves[0]);
    pool2 = raw2(reserves[1]);
    poolK = pool1 * pool2;
    price2 = pool1 / pool2;
    price1 = pool2 / pool1;

    // This is all LPs minted so far
    supplyLP = rawLP(await totalSupply());

    // Price of LP is calculated as the full pool valuated in Token2, divided by supply
    priceLP = ((pool1 * price1) + pool2) / supplyLP;
  }
}
