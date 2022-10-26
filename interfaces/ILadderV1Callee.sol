pragma solidity >=0.5.0;

interface ILadderV1Callee {
    function ladderV1Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}
