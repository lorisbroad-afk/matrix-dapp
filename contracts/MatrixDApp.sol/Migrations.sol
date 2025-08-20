// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Migrations {
    address public owner = msg.sender;

    function setCompleted(uint completed) public {
        require(msg.sender == owner, "Only owner can set completed");
    }
}