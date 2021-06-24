# Returning Externally Owned Account checks to EIP3074

The recently proposed [EIP3074](https://eips.ethereum.org/EIPS/eip-3074) allows a user to delegate control 
of their account to a smart contract, optionally setting `msg.sender` to `tx.origin` 
(the address that created the tx) for the next call using the `AUTH`/`AUTHCALL` opcodes.

This breaks existing contracts that use those variables to check whether the
caller is a non-contract account (an EOA), with many saying that it's a good thing
it does because it's not a check that should be relied on for many reasons and 
breaks Ethereum's composability. For fun, I wanted to see if there was still a 
way to detect whether a caller was an EOA, even without using `tx.origin` at all.

Enter [EIP150](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-150.md): one of its changes,
partly adopted as an anti-DoS measure, is a mechanic added to all \*CALL opcodes which
restricts the gas passed to next call to be `(63/64)*gasleft`.

This can be used as a hack to check whether a call to a contract is a top-level
call (from an EOA) rather than from a contract, by setting `gas_allowance =
block.gaslimit`.

Since there is no way to have an allowance or a gasleft > block.gaslimit, even
without the ability to know what the top level call's gas allowance is, this
can be used to know if we are in a top level call by just ensuring that
`gasleft() > block.gaslimit*(63/64)`, as this check can never be true for
anything other than a top level (EOA) call.

Turing completeness strikes again!

# Make smart contracts EOA-safe again

The code in this repo implements an `EIP3074Protection` contract which can
be inherited to provide the `NoContracts` guard modifier that can be applied to
any function you don't want called by any other contract.

```solidity 
contract EIP3074Protection {
    
    bool protected = false;
    
    // be careful of re-entrancy, this modifier won't handle it 
    modifier NoContracts {
        bool top_level = false;
        if (!protected){
            require(gasleft() > ((block.gaslimit/64)*63), "Only EOAs can call this contract");
            protected = true;
            top_level = true;
        }
        _;
        if (top_level) {
            protected = false;
        }
    }
}
```

Inheriting and applying the modifier prevents any outside contract from calling the guarded function,
but allows the contract's function to call each other still due to the protected state flag:

```solidity
contract OnlyEOAs is EIP3074Protection {
    
    event Success(bool val);

    function doSomething() NoContracts public {
        emit Success(true);
    }

    function doSomethingElse() NoContracts public {
        // contract can internally call any other functions that have NoContracts modifier
        // but they can't be called from an outsider contract
        doSomething(); 
    }
    
}
```

But any outside contract performing a call to the guarded functions will fail:

```solidity
contract EIP3074ProtectionTest {
    function tryCallingProtected(OnlyEOAs target) external {
        target.doSomething(); // this call will revert
    }
}
```

To test, just install eth-brownie and ganache-cli and run:

`brownie run scripts/eip3074.py`

You will see the following output:

```
Brownie v1.14.6 - Python development framework for Ethereum

EipbreakProject is the active project.

Launching 'ganache-cli --port 8545 --gasLimit 12000000 --accounts 10 --hardfork istanbul --mnemonic brownie'...

Running 'scripts/eip3074.py::main'...
Transaction sent: 0x56b7e09ba369a721de5047d4ee80ed8f2532105f1e29ec30c8b271b2282e3b5c
  Gas price: 20.0 gwei   Gas limit: 12000000   Nonce: 0
  OnlyEOAs.constructor confirmed - Block: 1   Gas used: 197355 (1.64%)
  OnlyEOAs deployed at: 0x3194cBDC3dbcd3E11a07892e7bA5c3394048Cc87

Transaction sent: 0xfbf05cdffc06d37d5ecbf1db82d724fb6ad39f83da934b0f00b8f061746b3411
  Gas price: 20.0 gwei   Gas limit: 12000000   Nonce: 1
  OnlyEOAs.doSomething confirmed - Block: 2   Gas used: 27831 (0.23%)

Gas ratio: 63.882528
Transaction sent: 0x0a8ea867c833991be2d83591aa0af73e7ad24b362d6b62e19f8dcbdf54ccb311
  Gas price: 20.0 gwei   Gas limit: 12000000   Nonce: 2
  OnlyEOAs.doSomethingElse confirmed - Block: 3   Gas used: 31898 (0.27%)

Gas ratio: 63.882645333333336
Transaction sent: 0x9b3622905e6a91e3c8c5418724afcaf9490e04a0fa04ca07122a078fce84952a
  Gas price: 20.0 gwei   Gas limit: 12000000   Nonce: 3
  EIP3074ProtectionTest.constructor confirmed - Block: 4   Gas used: 106491 (0.89%)
  EIP3074ProtectionTest deployed at: 0x6951b5Bd815043E3F842c1b026b0Fa888Cc2DD85

Transaction sent: 0x298ed4b8189c815c0b645534bce055574192b8dc7c1aa06db8e6d18f3cc6e05e
  Gas price: 20.0 gwei   Gas limit: 12000000   Nonce: 4
  EIP3074ProtectionTest.tryCallingProtected confirmed (Only EOAs can call this contract) - Block: 5   Gas used: 25804 (0.22%)

  File "brownie/_cli/run.py", line 50, in main
    args["<filename>"], method_name=args["<function>"] or "main", _include_frame=True
  File "brownie/project/scripts.py", line 103, in run
    return_value = f_locals[method_name](*args, **kwargs)
  File "./scripts/eip3074.py", line 24, in main
    tx = protectionTest.tryCallingProtected(eoaContract)
  File "brownie/network/contract.py", line 1676, in __call__
    return self.transact(*args)
  File "brownie/network/contract.py", line 1559, in transact
    allow_revert=tx["allow_revert"],
  File "brownie/network/account.py", line 645, in transfer
    receipt._raise_if_reverted(exc)
  File "brownie/network/transaction.py", line 394, in _raise_if_reverted
    source=source, revert_msg=self._revert_msg, dev_revert_msg=self._dev_revert_msg
VirtualMachineError: revert: Only EOAs can call this contract
Trace step -1, program counter 138:
  File "contracts/EIP3074Protection.sol", line 40, in EIP3074ProtectionTest.tryCallingProtected:    
    contract EIP3074ProtectionTest {

        function tryCallingProtected(OnlyEOAs target) external {
            target.doSomething();
        }
    }
Terminating local RPC client...

```

As expected, the first two direct calls succeed, and the call that happens
through a second contract fails.

- Matt
