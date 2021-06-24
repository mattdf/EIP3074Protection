// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract EIP3074Protection {
    
    event GasInfo(uint256 txgas, uint256 gaslimit);

    bool protected = false;
    
    // be careful of re-entrancy, this modifier won't handle it 
    modifier NoContracts {
        bool top_level = false;
        if (!protected){
            emit GasInfo(gasleft(), block.gaslimit);
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

contract EIP3074ProtectionTest {

    function tryCallingProtected(OnlyEOAs target) external {
        target.doSomething();
    }
}
