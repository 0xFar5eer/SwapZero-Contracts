// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import "./swzERC1155.sol";
import "./openzeppelin-contracts-4.6.0/contracts/token/ERC20/IERC20.sol";
import "./openzeppelin-contracts-4.6.0/contracts/security/ReentrancyGuard.sol";

import "./TestErc20Token.sol";

contract SwapZero is swzERC1155, ReentrancyGuard {

    address constant DEAD_ADDRESS = address(0xDEAD); // here can be well known null address, nobody has access to it
    uint256 constant MINIMUM_LIQUIDITY = 1_000;

    // 0x0000000000000000000000000000000000000000 1000000000000000000
    IERC20 constant NATIVE_TOKEN = IERC20(address(0)); // we use null address for native tokens

    IERC20 swzToken;
    Pool[] listOfPools;

    mapping(IERC20 => uint256) tokenAddressToPoolId;

    uint256 TRADE_FEE_NOMINATOR = 25; // 0.25% = 25/10,000
    uint256 TRADE_FEE_DENOMINATOR = 10_000;
    uint256 TRADE_FEE_DENOMINATOR_MINUS_NOMINATOR = TRADE_FEE_DENOMINATOR - TRADE_FEE_NOMINATOR;

    struct Pool {
        IERC20 tokenInPool;
        uint256 swzTokenBalance;
    }

    event PoolCreated(
        IERC20 indexed _token,
        uint256 _poolId
    );

    event LiquidityAdded(
        IERC20 indexed _token,
        uint256 _amountTokensIn,
        uint256 _amountSwzTokensIn,
        uint256 _lpTokensAmount,
        address _transferTo
    );

    event LiquidityRemoved(
        IERC20 indexed _token,
        uint256 _amountTokensOut,
        uint256 _amountSwzTokensOut,
        uint256 _lpTokensAmount,
        address _transferTo
    );

    event Swap(
        IERC20 indexed _token,
        uint256 _amountTokensIn,
        uint256 _amountSwzTokensIn,
        uint256 _amountTokensOut,
        uint256 _amountSwzTokensOut
    );

    event Sync(
        IERC20 indexed _token,
        uint256 _newBalanceToken,
        uint256 _newBalanceSwz
    );

    ITestErc20Token testTokenIn;
    ITestErc20Token testTokenOut;
    function test1_CreateTokensAndPools()
        public
    {
        testTokenIn = ITestErc20Token(address(new TestErc20Token("TokenIn", "T_IN")));
        testTokenOut = ITestErc20Token(address(new TestErc20Token("TokenOut", "T_OUT")));
        swzToken = ITestErc20Token(address(new TestErc20Token("SWZ", "SWZ")));

        testTokenIn.mint(msg.sender, 1e12 * 1e18);
        testTokenOut.mint(msg.sender, 1e12 * 1e18);
        ITestErc20Token(address(swzToken)).mint(msg.sender, 1e12 * 1e18);

        createPool(testTokenIn);
        createPool(testTokenOut);
        createPool(NATIVE_TOKEN);

        addLiquidity(
            testTokenIn,
            1e6 * 1e18,
            1e9 * 1e18,
            msg.sender
        );
        addLiquidity(
            testTokenOut,
            1e9 * 1e18,
            1e9 * 1e18,
            msg.sender
        );
    }
    function test2_CreateNativeTokenAndPool()
        public
        payable
    {
        addLiquidity(
            NATIVE_TOKEN,
            1 * 1e18,
            1e9,
            msg.sender
        );
    }
    function test3_AddLiquidity_RemoveLiqudity()
        public
    {
        (uint256 reservesTokenIn, uint256 reservesSwzTokenOut) = getPoolBalances(testTokenIn);

        uint256 initialAmountOfTokenIn = 1e3 * 1e18;
        uint256 initialAmountOfSwzToken = (initialAmountOfTokenIn * reservesSwzTokenOut) / reservesTokenIn;

        uint256 amountOfLiquidity = addLiquidity(
            testTokenIn,
            initialAmountOfTokenIn,
            initialAmountOfSwzToken,
            msg.sender
        );

        (uint256 amountOfTokensOut, uint256 amountOfSwzTokensOut) = removeLiquidity(
            testTokenIn,
            amountOfLiquidity,
            msg.sender
        );

        require(amountOfTokensOut < initialAmountOfTokenIn, "amountOfTokensOut <= initialAmountOfTokenIn");
        require(amountOfSwzTokensOut < initialAmountOfSwzToken, "amountOfSwzTokensOut <= initialAmountOfSwzToken");
    }
    function test4_AddLiquidity_SwapAndBack_RemoveLiqudity()
        public
    {
        (uint256 reservesTokenIn, uint256 reservesSwzTokenOut) = getPoolBalances(testTokenIn);

        uint256 initialAmountOfTokens = 1e3 * 1e18;

        uint256 addLiquidityTokens = initialAmountOfTokens * 2 / 3;
        uint256 addLiquiditySwz = (addLiquidityTokens * reservesSwzTokenOut) / reservesTokenIn;

        uint256 amountOfLiquidity = addLiquidity(
            testTokenIn,
            addLiquidityTokens,
            addLiquiditySwz,
            msg.sender
        );

        uint256 swapTokensAmount = initialAmountOfTokens / 3;
        uint256 receivedSwzTokens = swapExactTokensForTokens(
            testTokenIn,
            swzToken,
            swapTokensAmount,
            msg.sender
        );
        uint256 receivedTokens = swapExactTokensForTokens(
            swzToken,
            testTokenIn,
            receivedSwzTokens,
            msg.sender
        );

        require(receivedTokens < swapTokensAmount, "receivedTokens < swapTokensAmount");

        (uint256 amountOfTokensOut, uint256 amountOfSwzTokensOut) = removeLiquidity(
            testTokenIn,
            amountOfLiquidity,
            msg.sender
        );

        require(receivedTokens + amountOfTokensOut < initialAmountOfTokens, "receivedTokens + amountOfTokensOut < initialAmountOfTokens");
        require(amountOfSwzTokensOut < addLiquiditySwz, "amountOfSwzTokensOut < addLiquiditySwz");
    }
    function test5_SwapInToOutAndBack()
        public
    {
        uint256 initialTokensIn = 1e18;
        uint256 receivedTokensOut = swapExactTokensForTokens(
            testTokenIn,
            testTokenOut,
            initialTokensIn,
            msg.sender
        );
        uint256 receivedTokensIn = swapExactTokensForTokens(
            testTokenOut,
            testTokenIn,
            receivedTokensOut,
            msg.sender
        );

        require(receivedTokensIn < initialTokensIn, "receivedTokensIn < initialTokensIn");
    }
    function testGetTokenInAndTokenOut()
        public
        view
        returns(ITestErc20Token, ITestErc20Token, IERC20)
    {
        return (testTokenIn, testTokenOut, swzToken);
    }

    constructor() {
        // filling 0th element of pool as empty
        listOfPools.push(Pool({
            tokenInPool: IERC20(NATIVE_TOKEN),
            swzTokenBalance: 0
        }));
    }

    function createPool(IERC20 _tokenAddr)
        public
        returns(uint256)
    {
        require(_tokenAddr != swzToken, "Token must be different from SWZ Token");
        require(tokenAddressToPoolId[_tokenAddr] == 0, "Pool for this token already exists");

        // saving new poolId for this _tokenAddr
        // position of the pool in listOfPools array
        // starts from 1 because we filled 0th element with empty pool
        uint256 poolId = listOfPools.length;
        tokenAddressToPoolId[_tokenAddr] = poolId;

        // pushing new token to the pool array
        listOfPools.push(Pool({
            tokenInPool: _tokenAddr,
            swzTokenBalance: 0
        }));
    
        emit PoolCreated(
            _tokenAddr,
            poolId
        );
        return poolId;
    }

    function addLiquidity(
        IERC20 _tokenAddr,
        uint256 _amountTokensIn,
        uint256 _amountSwzTokensIn,
        address _transferTo
    )
        public
        payable
        nonReentrant // re-entrancy protection
        returns(uint256)
    {
        uint256 poolId = tokenAddressToPoolId[_tokenAddr];
        if (poolId == 0) {
            poolId = createPool(_tokenAddr);
        }

        // creating link to storage for further read/writes
        Pool storage pool = listOfPools[poolId];

        // balance of token in the pool before the transfers
        uint256 poolTokenBalanceBefore = _getTokenBalanceInPoolBefore(_tokenAddr);


        uint256 totalSupplyOfLiquidity = totalSupply(poolId);
        uint256 amountOfLiquidityToMint = 0;

        if (totalSupplyOfLiquidity == 0) {
            // minting 1000 lp tokens to null address as per uniswap v2 whitepaper
            // refer to 3.4 Initialization of liquidity token supply https://uniswap.org/whitepaper.pdf
            // minting ERC1155 token for dead address
            // refer to https://github.com/Uniswap/v2-core/blob/8b82b04a0b9e696c0e83f8b2f00e5d7be6888c79/contracts/UniswapV2Pair.sol#L119-L124
            _mint(
                DEAD_ADDRESS,
                poolId,
                MINIMUM_LIQUIDITY,
                ""
            );

            // refer to https://github.com/Uniswap/v2-core/blob/8b82b04a0b9e696c0e83f8b2f00e5d7be6888c79/contracts/UniswapV2Pair.sol#L119-L124            
            amountOfLiquidityToMint = _sqrt(_amountTokensIn * _amountSwzTokensIn) - MINIMUM_LIQUIDITY;
        } else {
            // it is Math.min(x1, x2)
            amountOfLiquidityToMint = _min(
                (_amountTokensIn * totalSupplyOfLiquidity) / poolTokenBalanceBefore,
                (_amountSwzTokensIn * totalSupplyOfLiquidity) / pool.swzTokenBalance
            );
        }

        require(amountOfLiquidityToMint > 0, "Insufficient amount of liquidity minted");

        // updating pool balance in storage
        pool.swzTokenBalance += _amountSwzTokensIn;

        // transferring token from msg sender to contract
        _safeTokenTransferFromMsgSender(_tokenAddr, _amountTokensIn);

        // SWZ token does not require additional checks
        swzToken.transferFrom(msg.sender, address(this), _amountSwzTokensIn);

        // minting ERC1155 token for user
        _mint(
            _transferTo,
            poolId,
            amountOfLiquidityToMint,
            ""
        );
        
        emit LiquidityAdded(
            _tokenAddr,
            _amountTokensIn,
            _amountSwzTokensIn,
            amountOfLiquidityToMint,
            _transferTo
        );

        emit Sync(
            _tokenAddr,
            poolTokenBalanceBefore + _amountTokensIn,
            pool.swzTokenBalance
        );

        return amountOfLiquidityToMint;
    }

    function removeLiquidity(
        IERC20 _tokenAddr,
        uint256 _amountOfLiquidityToRemove,
        address _transferTo
    )
        public
        nonReentrant // re-entrancy protection
        returns(uint256, uint256)
    {
        uint256 poolId = tokenAddressToPoolId[_tokenAddr];

        // creating link to storage for further read/writes
        Pool storage pool = listOfPools[poolId];

        // getting balance of token in the pool
        uint256 poolTokenBalanceBefore = _getTokenBalanceInPoolBefore(_tokenAddr);
        
        uint256 totalSupplyOfLiquidity = totalSupply(poolId);
        uint256 amountTokensOut = (poolTokenBalanceBefore * _amountOfLiquidityToRemove) / totalSupplyOfLiquidity;
        uint256 amountSwzTokensOut = (pool.swzTokenBalance * _amountOfLiquidityToRemove) / totalSupplyOfLiquidity;

        // updating pool balance in storage
        pool.swzTokenBalance -= amountSwzTokensOut;

        // burning ERC1155 token from user
        _burn(
            msg.sender,
            poolId,
            _amountOfLiquidityToRemove
        );

        // transferring tokens to user
        _safeTokenTransferToUser(_tokenAddr, _transferTo, amountTokensOut);

        // transferring SWZ tokens to user
        swzToken.transfer(_transferTo, amountSwzTokensOut);
        
        emit LiquidityAdded(
            _tokenAddr,
            amountTokensOut,
            amountSwzTokensOut,
            _amountOfLiquidityToRemove,
            _transferTo
        );

        emit Sync(
            _tokenAddr,
            poolTokenBalanceBefore - amountTokensOut,
            pool.swzTokenBalance
        );

        return (amountTokensOut, amountSwzTokensOut);
    }

    // TODO: swapTokensForExactTokens

    function swapExactTokensForTokens(
        IERC20 _tokenIn,
        IERC20 _tokenOut,
        uint256 _amountTokensIn,
        address _transferTo
    )
        public
        nonReentrant // re-entrancy protection
        returns(uint256)
    {
        require(_tokenIn != _tokenOut, "Can't swap the same token to itself");

        uint256 reservesIn;
        uint256 reservesOut;
        uint256 amountTokensOut;

        // swap [SWZ --> TokenOut]
        if (_tokenIn == swzToken) {
            (reservesOut, reservesIn) = getPoolBalances(_tokenOut);

            amountTokensOut = _getOutput(
                reservesIn,
                reservesOut,
                _amountTokensIn
            );
            
            _swap(
                _tokenOut,              // _tokenAddr
                reservesOut,            // _tokenBalanceBefore
                0,                      // _amountTokensIn
                _amountTokensIn,        // _amountSwzTokensIn
                amountTokensOut,        // _amountTokensOut
                0                       // _amountSwzTokensOut
            );

            // transferring SWZ tokens from user to contract
            swzToken.transferFrom(msg.sender, address(this), _amountTokensIn);

            // transferring tokens to user
            _safeTokenTransferToUser(_tokenOut, _transferTo, amountTokensOut);
            return amountTokensOut;
        }

        // swap [TokenIn --> SWZ]
        uint256 amountSwzTokensOut;
        if (_tokenOut == swzToken) {
            (reservesIn, reservesOut) = getPoolBalances(_tokenIn);

            amountSwzTokensOut = _getOutput(
                reservesIn,
                reservesOut,
                _amountTokensIn
            );
            
            _swap(
                _tokenIn,               // _tokenAddr
                reservesIn,             // _tokenBalanceBefore
                _amountTokensIn,        // _amountTokensIn
                0,                      // _amountSwzTokensIn
                0,                      // _amountTokensOut
                amountSwzTokensOut      // _amountSwzTokensOut
            );

            // transferring tokens from user to contract
            _safeTokenTransferFromMsgSender(_tokenIn, _amountTokensIn);

            // transferring SWZ tokens to user
            swzToken.transfer(_transferTo, amountSwzTokensOut);
            return amountSwzTokensOut;
        }

        // _tokenIn != swzToken && _tokenOut != swzToken
        // swap [TokenIn --> SWZ --> TokenOut], TokenIn != TokenOut
        (reservesIn, reservesOut) = getPoolBalances(_tokenIn);
        
        // calculating amount of swz tokens out from tokenIn pool
        // which will be transferred to tokenOut pool
        amountSwzTokensOut = _getOutput(
            reservesIn,
            reservesOut,
            _amountTokensIn
        );
        
        // swap [TokenIn --> SWZ]
        _swap(
            _tokenIn,               // _tokenAddr
            reservesIn,             // _tokenBalanceBefore
            _amountTokensIn,        // _amountTokensIn
            0,                      // _amountSwzTokensIn
            0,                      // _amountTokensOut
            amountSwzTokensOut     // _amountSwzTokensOut
        );

        (reservesOut, reservesIn) = getPoolBalances(_tokenOut);

        amountTokensOut = _getOutput(
            reservesIn,
            reservesOut,
            amountSwzTokensOut
        );
            
        // swap [SWZ --> TokenOut]
        _swap(
            _tokenOut,              // _tokenAddr
            reservesOut,            // _tokenBalanceBefore
            0,                      // _amountTokensIn
            amountSwzTokensOut,     // _amountSwzTokensIn
            amountTokensOut,        // _amountTokensOut
            0                       // _amountSwzTokensOut
        );

        // transferring tokens from user to contract
        _safeTokenTransferFromMsgSender(_tokenIn, _amountTokensIn);

        // transferring tokens to user
        _safeTokenTransferToUser(_tokenOut, _transferTo, amountTokensOut);

        return amountTokensOut;
    }

    // core swap function
    // to swap [Token --> SWZ] or [SWZ --> Token]
    function _swap(
        IERC20 _tokenAddr,
        uint256 _tokenBalanceBefore,
        uint256 _amountTokensIn,
        uint256 _amountSwzTokensIn,
        uint256 _amountTokensOut,
        uint256 _amountSwzTokensOut
    )
        private
    {
        uint256 poolId = tokenAddressToPoolId[_tokenAddr];
        Pool storage pool = listOfPools[poolId];

        // calculating K value before the swap
        uint256 kValueBefore = _tokenBalanceBefore * pool.swzTokenBalance;

        // calculating token balances after the swap
        uint256 tokenBalanceAfter = _tokenBalanceBefore + _amountTokensIn - _amountTokensOut;
        uint256 swzTokenBalanceAfter = pool.swzTokenBalance + _amountSwzTokensIn - _amountSwzTokensOut;

        // calculating new K value after the swap including trade fees
        // refer to 3.2.1 Adjustment for fee https://uniswap.org/whitepaper.pdf
        uint256 kValueAfter = 
            (tokenBalanceAfter - (_amountTokensIn * TRADE_FEE_NOMINATOR) / TRADE_FEE_DENOMINATOR) *
            (swzTokenBalanceAfter - (_amountSwzTokensIn * TRADE_FEE_NOMINATOR) / TRADE_FEE_DENOMINATOR);
        
        require(kValueAfter >= kValueBefore, "K value must increase or remain unchanged during any swap");

        // update pool values
        pool.swzTokenBalance = swzTokenBalanceAfter;

        emit Swap(
            _tokenAddr,
            _amountTokensIn,
            _amountSwzTokensIn,
            _amountTokensOut,
            _amountSwzTokensOut
        );

        emit Sync(
            _tokenAddr,
            tokenBalanceAfter,
            swzTokenBalanceAfter
        );
    }

    function _safeTokenTransferFromMsgSender(
        IERC20 _tokenAddr, 
        uint256 _tokenAmount
    )
        private
    {
        // we use NATIVE_TOKEN for native tokens
        // if address != null that means this is ERC20 token
        // if address == null that means this is native token (for example ETH)
        // for non-native tokens we have to get
        // exact amount of contract balance increase
        // after calling ERC20.transferFrom function
        if (_tokenAddr != NATIVE_TOKEN) {
            // non native tokens requires checking for fee-on-transfer
            uint256 tokenBalanceBefore = _tokenAddr.balanceOf(address(this));            
            _tokenAddr.transferFrom(msg.sender, address(this), _tokenAmount);
            uint256 tokenBalanceAfter = _tokenAddr.balanceOf(address(this));

            // we revert if user sent us less tokens than needed after calling ERC20.transferFrom
            uint256 realTransferredAmount = tokenBalanceAfter - tokenBalanceBefore;
            require(realTransferredAmount == _tokenAmount, "Fee on transfer tokens aren't supported");

            // if user sent native tokens we revert here
            require(msg.value == 0, "User mustn't send native tokens here");
            return;
        }        
        
        // native token
        // don't need to do anything
        // because native tokens already transferred to contract
        require(_tokenAmount == msg.value, "User must provide correct amount of native tokens");
    }

    function _safeTokenTransferToUser(
        IERC20 _tokenAddr,
        address _transferTo,
        uint256 _tokenAmount
    )
        private
    {
        // we use NATIVE_TOKEN for native tokens
        // if address != null that means this is ERC20 token
        // if address == null that means this is native token (for example ETH)
        if (_tokenAddr != NATIVE_TOKEN) {           
            _tokenAddr.transfer(_transferTo, _tokenAmount);
            return;
        }        
        
        // native token transfer
        payable(_transferTo).transfer(_tokenAmount);
    }

    function _getTokenBalanceInPoolBefore(IERC20 _tokenAddr)
        private
        view
        returns(uint256)
    {
        require(tokenAddressToPoolId[_tokenAddr] > 0, "Pool with this token must exist");

        uint256 tokenBalanceBefore = 0;
        if (_tokenAddr == NATIVE_TOKEN) {
            // user already transferred native tokens to the contract
            // to know balance before the transfer we have to substract it
            tokenBalanceBefore = address(this).balance - msg.value;
            return tokenBalanceBefore;
        } 

        // for ERC20 tokens
        tokenBalanceBefore = _tokenAddr.balanceOf(address(this));
        return tokenBalanceBefore;
    }


    function getPoolBalances(IERC20 _tokenAddr)
        public
        view
        returns(uint256, uint256)
    {
        uint256 poolId = tokenAddressToPoolId[_tokenAddr];
        uint256 swzTokenBalanceBefore = listOfPools[poolId].swzTokenBalance;

        uint256 tokenBalanceBefore = _getTokenBalanceInPoolBefore(_tokenAddr);
        return (tokenBalanceBefore, swzTokenBalanceBefore);
    }

    function getPoolBalances(uint256 _poolId)
        public
        view
        returns(uint256, uint256)
    {
        uint256 swzTokenBalanceBefore = listOfPools[_poolId].swzTokenBalance;

        uint256 tokenBalanceBefore = _getTokenBalanceInPoolBefore(listOfPools[_poolId].tokenInPool);
        return (tokenBalanceBefore, swzTokenBalanceBefore);
    }

    function getExactTokensForTokens(
        IERC20 _tokenIn,
        IERC20 _tokenOut,
        uint256 _amountIn
    )
        public
        view
        returns(uint256)
    {
        require(_tokenIn != _tokenOut, "Can't swap the same token to itself");

        uint256 reservesOut;
        uint256 reservesIn;

        // swap [SWZ --> TokenOut]
        if (_tokenIn == swzToken) {
            (reservesOut, reservesIn) = getPoolBalances(_tokenOut);

            return _getOutput(
                reservesIn,
                reservesOut,
                _amountIn
            );
        }

        // swap [TokenIn --> SWZ]
        if (_tokenOut == swzToken) {
            (reservesIn, reservesOut) = getPoolBalances(_tokenIn);

            return _getOutput(
                reservesIn,
                reservesOut,
                _amountIn
            );
        }

        // _tokenIn != swzToken && _tokenOut != swzToken
        // swap [TokenIn --> SWZ --> TokenOut], TokenIn != TokenOut
        (reservesIn, reservesOut) = getPoolBalances(_tokenIn);
        
        // calculating amount of swz tokens out from tokenIn pool
        // which will be transferred to tokenOut pool
        _amountIn = _getOutput(
            reservesIn,
            reservesOut,
            _amountIn
        );

        (reservesOut, reservesIn) = getPoolBalances(_tokenOut);
        return _getOutput(
            reservesIn,
            reservesOut,
            _amountIn
        );
    }

    function getTokensForExactTokens(
        IERC20 _tokenIn,
        IERC20 _tokenOut,
        uint256 _amountOut
    )
        public
        view
        returns(uint256)
    {
        require(_tokenIn != _tokenOut, "Can't swap the same token to itself");

        uint256 reservesOut;
        uint256 reservesIn;

        // swap [SWZ --> Token]
        if (_tokenIn == swzToken) {
            (reservesOut, reservesIn) = getPoolBalances(_tokenOut);

            return _getInput(
                reservesIn,
                reservesOut,
                _amountOut
            );
        }

        // swap [Token --> SWZ]
        if (_tokenOut == swzToken) {
            (reservesIn, reservesOut) = getPoolBalances(_tokenIn);

            return _getInput(
                reservesIn,
                reservesOut,
                _amountOut
            );
        }

        // _tokenIn != swzToken && _tokenOut != swzToken
        // swap [Token1 --> SWZ --> Token2], Token1 != Token2
        (reservesOut, reservesIn) = getPoolBalances(_tokenOut);
        
        // calculating amount of swz tokens in to tokenOut pool
        // based on that calculating amount of tokens in to tokenIn pool
        _amountOut = _getInput(
            reservesIn,
            reservesOut,
            _amountOut
        );

        (reservesIn, reservesOut) = getPoolBalances(_tokenIn);

        return _getInput(
            reservesIn,
            reservesOut,
            _amountOut
        );
    }

    function _getOutput(
        uint256 _reservesIn,
        uint256 _reservesOut,
        uint256 _amountIn
    )
        private
        view
        returns (uint256)
    {
        // refer to https://github.com/Uniswap/v2-periphery/blob/2efa12e0f2d808d9b49737927f0e416fafa5af68/contracts/libraries/UniswapV2Library.sol#L43-L50
        uint256 amountInWithFee = _amountIn * TRADE_FEE_DENOMINATOR_MINUS_NOMINATOR;

        return (amountInWithFee * _reservesOut) / 
            (_reservesIn * TRADE_FEE_DENOMINATOR + amountInWithFee);
    }

    function _getInput(
        uint256 _reservesIn,
        uint256 _reservesOut,
        uint256 _amountOut
    )
        internal
        view
        returns (uint256)
    {
        // refer to https://github.com/Uniswap/v2-periphery/blob/2efa12e0f2d808d9b49737927f0e416fafa5af68/contracts/libraries/UniswapV2Library.sol#L53-L59
        return (_reservesIn * _amountOut * TRADE_FEE_DENOMINATOR) /
            (TRADE_FEE_DENOMINATOR_MINUS_NOMINATOR * (_reservesOut - _amountOut)) +
            1; // adding +1 for any rounding trims
    }

    function _min(uint256 x1, uint256 x2)
        private
        pure
        returns (uint256)
    {
        if (x1 < x2) return x1;

        return x2;
    }

    function _sqrt(
        uint256 _y
    )
        private
        pure
        returns (uint256 z)
    {
        if (_y > 3) {
            z = _y;
            uint256 x = _y / 2 + 1;
            while (x < z) {
                z = x;
                x = (_y / x + x) / 2;
            }
        } else if (_y != 0) {
            z = 1;
        }
    }
}
