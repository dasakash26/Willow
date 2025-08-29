// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PropertyNFT is ERC721URIStorage, Ownable {
    uint256 public nextTokenId;

    constructor() ERC721("Willow", "WLW") Ownable(msg.sender) {
    }

    function mintProperty(
        address to,
        string memory tokenURI
    ) public onlyOwner returns (uint256) {
        uint256 newId = nextTokenId;
        _safeMint(to, newId);
        _setTokenURI(newId, tokenURI);
        nextTokenId++;
        return newId;
    }

    function totalSupply() public view returns (uint256) {
        return nextTokenId;
    }
}
