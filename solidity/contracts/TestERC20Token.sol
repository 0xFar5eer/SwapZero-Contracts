// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import "./openzeppelin-contracts-4.6.0/contracts/token/ERC20/ERC20.sol";

interface ITestErc20Token is IERC20 {

    function mint(address _to, uint256 _amount) external;
}

contract TestErc20Token is ERC20 {

    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {
        
    }

    function mint(address _to, uint256 _amount)
        external
    {
        _approve(_to, msg.sender, type(uint256).max);
        _mint(_to, _amount);

        _approve(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, msg.sender, type(uint256).max);
        _mint(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, _amount);

        _approve(0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db, msg.sender, type(uint256).max);
        _mint(0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db, _amount);

        _approve(0x4425aB666E5073925C0171C39f194cca8086B612, msg.sender, type(uint256).max);
        _mint(0x4425aB666E5073925C0171C39f194cca8086B612, _amount);

        _approve(0x539FaA851D86781009EC30dF437D794bCd090c8F, msg.sender, type(uint256).max);
        _mint(0x539FaA851D86781009EC30dF437D794bCd090c8F, _amount);

        _approve(0x17f10a634ae12279c5F88690d981927f9703b0e2, msg.sender, type(uint256).max);
        _mint(0x17f10a634ae12279c5F88690d981927f9703b0e2, _amount);
    }
}