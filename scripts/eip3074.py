#!/usr/bin/python3

from brownie import network, OnlyEOAs, EIP3074ProtectionTest, EIP3074Protection, accounts

network.gas_limit(12000000)

network.gas_price(0)

def calcGasRatio(gasinfo):
	gasleft = gasinfo['txgas']
	gaslimit = gasinfo['gaslimit']

	return (float(gasleft)/float(gaslimit))*64.0


def main():
	eoaContract = OnlyEOAs.deploy({'from': accounts[0]})
	tx = eoaContract.doSomething()
	print("Gas ratio:", calcGasRatio(tx.events['GasInfo']))
	tx = eoaContract.doSomethingElse();
	print("Gas ratio:", calcGasRatio(tx.events['GasInfo']))

	protectionTest = EIP3074ProtectionTest.deploy({'from': accounts[0]})
	tx = protectionTest.tryCallingProtected(eoaContract)
