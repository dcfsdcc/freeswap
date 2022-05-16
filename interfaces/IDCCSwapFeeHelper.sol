// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.12;

import '../interfaces/IDCCSwapRouter.sol';

interface IDCCSwapFeeHelper {

    function getPathForTokenBridgeBusdToCake(IDCCSwapRouter router, address tokenAddress, address cakeAddress) external view  returns (address[] memory);
    function getPathForTokenBridgeUsdtToCake(IDCCSwapRouter router, address tokenAddress, address cakeAddress) external view  returns (address[] memory);
    function findPairByBusd(IDCCSwapRouter router, address tokenOutput, uint256 minDCCValueAllow, address cakeAddress) external view  returns (bool findPair);
    function findPairByUsdt(IDCCSwapRouter router, address tokenOutput, uint256 minDCCValueAllow, address cakeAddress) external view  returns (bool findPair);
    function findPairByBusdUsdt(IDCCSwapRouter router, address tokenA, address tokenB,  uint256 minDCCValueAllow, address cakeAddress) external view  returns (bool findPair);
    function findPairByToken0Token1CakeAddress(IDCCSwapRouter router,  address tokenA, address tokenB,uint256 minDCCValueAllow,address cakeAddress) external view  returns (bool );
    function getTokenPriceByDcc(IDCCSwapRouter router,  address token0) external view returns (uint256 );
    function computeDccValueByInputOutput(IDCCSwapRouter router, address input, address output, uint256 minDCCValueAllow) external view returns (bool );
    function computeDccValueByInputOutputNotWDCC(IDCCSwapRouter router, address input, address output, uint256 minDCCValueAllow) external view returns (bool findPair);

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(
        address factory,
        uint256 amountIn,
        address[] memory path
    ) external view returns (uint256[] memory amounts, uint256[] memory amountFees) ;

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(
        address factory,
        uint256 amountOut,
        address[] memory path
    ) external view returns (uint256[] memory amounts, uint256[] memory amountFees);



}
