// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

import "../interfaces/IDCCSwapPair.sol";
import "../interfaces/IDCCSwapFactory.sol";
import "./DCCSwapSafeMath.sol";

library DCCSwapUSDTLibrary {
    using DCCSwapSafeMath for uint256;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "DCCSwapLibrary::sortTokens::IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "DCCSwapLibrary::sortTokens::ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(
        address factory,
        address tokenA,
        address tokenB
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        factory,
                        keccak256(abi.encodePacked(token0, token1)),
                    // hex"3ed43c12bec6c972440efc73f18e7cb2857a20509c85b70001903ec594362116" // init code hash
                            //    hex"509d55c486282275cc14c223959609823cc08228b03ccfbfc77f46ce44888fa0" // init code hash   线上版本
                        // hex"651be81169ed1b38d3abafc58b72d7e81bdfd6f129369c09016380c3a35553cd" // lance test
                        hex"9b30efe4b3e4a02109db26b859a358fcd2be72cfd14c4fe4dab248343ed98e17" //queen
                    )
                )
            )
        );
    }

    // fetches and sorts the reserves for a pair
    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IDCCSwapPair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "DCCSwapLibrary::quote::INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "DCCSwapLibrary::quote::INSUFFICIENT_LIQUIDITY");
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        address factory,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut, uint256 amountOutFee) {
        require(amountIn > 0, "DCCSwapLibrary::getAmountOut::INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "DCCSwapLibrary::getAmountOut::INSUFFICIENT_LIQUIDITY");
        address feeTo = IDCCSwapFactory(factory).feeTo();
        uint256 lpFee = IDCCSwapFactory(factory).lpFee();
        uint256 lpFeeRateMax = IDCCSwapFactory(factory).lpFeeRateMax();

        require(lpFee > 0, "DCCSwapLibrary::getAmountOut::LPFEE_CANNOT_BE_ZERO");
        require(lpFeeRateMax > 0, "DCCSwapLibrary::getAmountOut::lpFeeRateMax_CANNOT_BE_ZERO");
        require(lpFeeRateMax > lpFee, "DCCSwapLibrary::getAmountOut::LPFEE_CANNOT_GREAT_THAN_LPFEERATEMAX");
        {
            uint256 lpFeeLeft = lpFeeRateMax.sub(lpFee);
            //    uint256 amountInWithFee = amountIn.mul(9980);
            uint256 amountInWithFee = amountIn.mul(lpFeeLeft);
            uint256 numerator = amountInWithFee.mul(reserveOut);
            uint256 denominator = reserveIn.mul(lpFeeRateMax).add(amountInWithFee);
            //    uint256 denominator = reserveIn.mul(10000).add(amountInWithFee);
            amountOut = numerator / denominator;
        }

        {
            uint256 amountInFee = amountIn.mul(lpFee);
            uint256 numeratorFee = amountInFee.mul(reserveOut);
            uint256 denominatorFee = reserveIn.mul(lpFeeRateMax);

            uint256 amountInDenominator = amountIn.mul(lpFeeRateMax);
            denominatorFee = denominatorFee.add(amountInDenominator);

            amountOutFee = numeratorFee / denominatorFee;
        }
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        address factory,
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn, uint256 amountInFee) {
        require(amountOut > 0, "DCCSwapLibrary::getAmountIn::INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "DCCSwapLibrary::getAmountIn::INSUFFICIENT_LIQUIDITY");

        uint256 lpFee = IDCCSwapFactory(factory).lpFee();
        uint256 lpFeeRateMax = IDCCSwapFactory(factory).lpFeeRateMax();

        require(lpFee > 0, "DCCSwapLibrary::getAmountOut::LPFEE_CANNOT_BE_ZERO");
        require(lpFeeRateMax > 0, "DCCSwapLibrary::getAmountOut::lpFeeRateMax_CANNOT_BE_ZERO");
        require(lpFeeRateMax > lpFee, "DCCSwapLibrary::getAmountOut::LPFEE_CANNOT_GREAT_THAN_LPFEERATEMAX");
        uint256 lpFeeLeft = lpFeeRateMax.sub(lpFee);

        uint256 numerator = reserveIn.mul(amountOut).mul(lpFeeRateMax);
        uint256 denominator = reserveOut.sub(amountOut).mul(lpFeeLeft);

        //    uint256 numerator = reserveIn.mul(amountOut).mul(10000);
        //    uint256 denominator = reserveOut.sub(amountOut).mul(9980);
        amountIn = (numerator / denominator).add(1);


        uint256 numeratorFee = reserveIn.mul(amountOut).mul(lpFeeRateMax);
        uint256 denominatorFee = reserveOut.sub(amountOut);
        //整除，再相减

        amountInFee = amountIn.sub((numeratorFee / denominatorFee) / lpFeeRateMax);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(
        address factory,
        uint256 amountIn,
        address[] memory path
    ) internal view returns (uint256[] memory amounts, uint256[] memory amountFees) {
        require(path.length >= 2, "DCCSwapLibrary::getAmountsOut::INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amountFees = new uint256[](path.length);
        amountFees[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            (amounts[i + 1], amountFees[i + 1]) = (amounts[i] == 0) ? (0, 0) : getAmountOut(factory, amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(
        address factory,
        uint256 amountOut,
        address[] memory path
    ) internal view returns (uint256[] memory amounts, uint256[] memory amountFees) {
        require(path.length >= 2, "DCCSwapLibrary::getAmountsIn::INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        amountFees = new uint256[](path.length);
        amountFees[amountFees.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            (amounts[i - 1], amountFees[i - 1]) =  (amounts[i] == 0) ? (0, 0) : getAmountIn(factory, amounts[i], reserveIn, reserveOut);
        }
    }
    
}
