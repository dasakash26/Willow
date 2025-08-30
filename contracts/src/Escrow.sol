//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RealEstateEscrow is ReentrancyGuard {
    address public immutable nftAddress;

    enum State {
        LISTED,
        AWAITING_FUNDS,
        AWAITING_INSPECTION,
        AWAITING_APPROVAL,
        FINALIZED,
        CANCELLED
    }

    struct Sale {
        address payable seller;
        address buyer;
        address inspector;
        address lender;
        uint256 purchasePrice;
        uint256 escrowAmount;
        uint256 fundsDeposited;
        State state;
        bool inspectionPassed;
        mapping(address => bool) approvals;
    }

    mapping(uint256 => Sale) public sales;

    event SaleListed(
        uint256 indexed nftID,
        address indexed seller,
        address indexed buyer,
        uint256 purchasePrice
    );
    event FundsDeposited(
        uint256 indexed nftID,
        address indexed depositor,
        uint256 amount
    );
    event InspectionUpdated(
        uint256 indexed nftID,
        address indexed inspector,
        bool passed
    );
    event SaleApproved(uint256 indexed nftID, address indexed approver);
    event SaleFinalized(
        uint256 indexed nftID,
        address buyer,
        address seller,
        uint256 amount
    );
    event SaleCancelled(uint256 indexed nftID);
    event FundsWithdrawn(
        uint256 indexed nftID,
        address indexed recipient,
        uint256 amount
    );

    constructor(address _nftAddress) {
        nftAddress = _nftAddress;
    }

    function list(
        uint256 _nftID,
        address _buyer,
        address _inspector,
        address _lender,
        uint256 _purchasePrice,
        uint256 _escrowAmount
    ) external nonReentrant {
        require(
            IERC721(nftAddress).ownerOf(_nftID) == msg.sender,
            "Only the NFT owner can list it."
        );
        require(
            sales[_nftID].seller == address(0),
            "This NFT is already listed for sale."
        );
        require(
            _purchasePrice > _escrowAmount,
            "Purchase price must be greater than escrow amount."
        );

        IERC721(nftAddress).transferFrom(msg.sender, address(this), _nftID);

        Sale storage newSale = sales[_nftID];
        newSale.seller = payable(msg.sender);
        newSale.buyer = _buyer;
        newSale.inspector = _inspector;
        newSale.lender = _lender;
        newSale.purchasePrice = _purchasePrice;
        newSale.escrowAmount = _escrowAmount;
        newSale.state = State.LISTED;

        emit SaleListed(_nftID, msg.sender, _buyer, _purchasePrice);
    }

    function depositFunds(uint256 _nftID) external payable {
        Sale storage currentSale = sales[_nftID];
        require(
            msg.sender == currentSale.buyer || msg.sender == currentSale.lender,
            "Only buyer or lender can deposit funds."
        );
        require(
            currentSale.state == State.LISTED ||
                currentSale.state == State.AWAITING_FUNDS,
            "Sale is not in a valid state for deposits."
        );

        currentSale.fundsDeposited += msg.value;

        if (
            currentSale.fundsDeposited >= currentSale.escrowAmount &&
            currentSale.state == State.LISTED
        ) {
            currentSale.state = State.AWAITING_INSPECTION;
        }

        if (currentSale.fundsDeposited >= currentSale.purchasePrice) {
            currentSale.state = State.AWAITING_APPROVAL;
        }

        emit FundsDeposited(_nftID, msg.sender, msg.value);
    }

    function updateInspectionStatus(uint256 _nftID, bool _passed) external {
        Sale storage currentSale = sales[_nftID];
        require(
            msg.sender == currentSale.inspector,
            "Only the inspector can update status."
        );
        require(
            currentSale.state == State.AWAITING_INSPECTION,
            "Sale is not awaiting inspection."
        );

        currentSale.inspectionPassed = _passed;

        if (_passed) {
            if (currentSale.fundsDeposited >= currentSale.purchasePrice) {
                currentSale.state = State.AWAITING_APPROVAL;
            } else {
                currentSale.state = State.AWAITING_FUNDS;
            }
        } else {
            currentSale.state = State.CANCELLED;
            emit SaleCancelled(_nftID);
        }

        emit InspectionUpdated(_nftID, msg.sender, _passed);
    }

    function approveSale(uint256 _nftID) external {
        Sale storage currentSale = sales[_nftID];
        require(
            currentSale.state == State.AWAITING_APPROVAL,
            "Sale is not awaiting approval."
        );
        require(
            msg.sender == currentSale.buyer ||
                msg.sender == currentSale.seller ||
                msg.sender == currentSale.lender,
            "You are not a party to this sale."
        );

        currentSale.approvals[msg.sender] = true;
        emit SaleApproved(_nftID, msg.sender);
    }

    function finalizeSale(uint256 _nftID) external nonReentrant {
        Sale storage currentSale = sales[_nftID];
        require(
            currentSale.state == State.AWAITING_APPROVAL,
            "Sale is not ready to be finalized."
        );
        require(currentSale.inspectionPassed, "Inspection must be passed.");
        require(
            currentSale.fundsDeposited >= currentSale.purchasePrice,
            "Full purchase price has not been deposited."
        );

        require(
            currentSale.approvals[currentSale.buyer],
            "Buyer has not approved."
        );
        require(
            currentSale.approvals[currentSale.seller],
            "Seller has not approved."
        );

        if (currentSale.lender != address(0)) {
            require(
                currentSale.approvals[currentSale.lender],
                "Lender has not approved."
            );
        }

        currentSale.state = State.FINALIZED;
        uint256 amountToSeller = currentSale.purchasePrice;

        (bool success, ) = currentSale.seller.call{value: amountToSeller}("");
        require(success, "Failed to transfer funds to seller.");

        IERC721(nftAddress).transferFrom(
            address(this),
            currentSale.buyer,
            _nftID
        );

        emit SaleFinalized(
            _nftID,
            currentSale.buyer,
            currentSale.seller,
            amountToSeller
        );
    }

    function cancelSale(uint256 _nftID) external {
        Sale storage currentSale = sales[_nftID];
        require(
            msg.sender == currentSale.buyer || msg.sender == currentSale.seller,
            "Only buyer or seller can cancel."
        );
        require(
            currentSale.state == State.AWAITING_FUNDS ||
                currentSale.state == State.AWAITING_APPROVAL,
            "Sale cannot be cancelled at this stage."
        );

        currentSale.state = State.CANCELLED;
        emit SaleCancelled(_nftID);
    }

    function withdrawFunds(uint256 _nftID) external nonReentrant {
        Sale storage currentSale = sales[_nftID];
        require(currentSale.state == State.CANCELLED, "Sale is not cancelled.");

        uint256 amountToWithdraw;
        address payable recipient;

        if (!currentSale.inspectionPassed) {
            require(
                msg.sender == currentSale.buyer,
                "Only buyer can withdraw on inspection failure."
            );
            amountToWithdraw = currentSale.fundsDeposited;
            recipient = payable(currentSale.buyer);
        } else {
            require(
                msg.sender == currentSale.seller,
                "Only seller can claim escrow after cancellation."
            );
            amountToWithdraw = currentSale.escrowAmount;
            recipient = currentSale.seller;

            uint256 refundToBuyer = currentSale.fundsDeposited -
                currentSale.escrowAmount;
            if (refundToBuyer > 0) {
                (bool refundSuccess, ) = payable(currentSale.buyer).call{
                    value: refundToBuyer
                }("");
                require(refundSuccess, "Failed to refund buyer.");
            }
        }

        require(amountToWithdraw > 0, "No funds to withdraw.");
        currentSale.fundsDeposited = 0; 

        (bool success, ) = recipient.call{value: amountToWithdraw}("");
        require(success, "Failed to withdraw funds.");

        emit FundsWithdrawn(_nftID, recipient, amountToWithdraw);
    }
}
