// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import "./openzeppelin-contracts-4.6.0/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

abstract contract swzERC1155 is ERC1155Supply {

    string contractName = "SwapZero";
    string contractSymbol = "SWZ_LP";
    string urlPrefix;

    constructor()
        ERC1155("") 
    {
    }

    function name()
        external
        view
        returns (string memory)
    {
        return contractName;
    }

    function symbol()
        external
        view
        returns (string memory)
    {
        return contractSymbol;
    }

    function decimals()
        external
        pure
        returns (uint256)
    {
        return 18;
    }
}
