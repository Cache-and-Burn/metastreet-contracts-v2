// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./interfaces/ILiquidity.sol";

/**
 * @title LoanReceipt
 * @author MetaStreet Labs
 */
library LoanReceipt {
    /**************************************************************************/
    /* Errors */
    /**************************************************************************/

    /**
     * @notice Invalid receipt encoding
     */
    error InvalidReceiptEncoding();

    /**
     * @notice Unsupported receipt version
     */
    error UnsupportedReceiptVersion();

    /**************************************************************************/
    /* Constants */
    /**************************************************************************/

    /**
     * @notice LoanReceiptV1 version
     */
    uint8 internal constant LOAN_RECEIPT_V1_VERSION = 1;

    /**
     * @notice LoanReceiptV1 header size in bytes
     * @dev Header excludes borrow options byte array
     */
    uint256 internal constant LOAN_RECEIPT_V1_HEADER_SIZE = 155;

    /**
     * @notice LoanReceiptV1 node receipt size in bytes
     */
    uint256 internal constant LOAN_RECEIPT_V1_NODE_RECEIPT_SIZE = 48;

    /**************************************************************************/
    /* Structures */
    /**************************************************************************/

    /**
     * @notice LoanReceiptV1
     * @param version Version (1)
     * @param principal Principal amount in currency tokens
     * @param repayment Repayment amount in currency tokens
     * @param borrower Borrower
     * @param maturity Loan maturity timestamp
     * @param duration Loan duration
     * @param collateralToken Collateral token
     * @param collateralTokenId Collateral token ID
     * @param collateralWrapperContextLen Collateral wrapper context length
     * @param collateralWrapperContext Collateral wrapper context data
     * @param nodeReceipts Node receipts
     */
    struct LoanReceiptV1 {
        uint8 version;
        uint256 principal;
        uint256 repayment;
        address borrower;
        uint64 maturity;
        uint64 duration;
        address collateralToken;
        uint256 collateralTokenId;
        uint16 collateralWrapperContextLen;
        bytes collateralWrapperContext;
        NodeReceipt[] nodeReceipts;
    }

    /**
     * @notice Node receipt
     * @param tick Tick
     * @param used Used amount
     * @param pending Pending amount
     */
    struct NodeReceipt {
        uint128 tick;
        uint128 used;
        uint128 pending;
    }

    /**************************************************************************/
    /* Tightly packed format */
    /**************************************************************************/

    /*
      Header (155 bytes)
          1   uint8   version                        0:1
          32  uint256 principal                      1:33
          32  uint256 repayment                      33:65
          20  address borrower                       65:85
          8   uint64  maturity                       85:93
          8   uint64  duration                       93:101
          20  address collateralToken                101:121
          32  uint256 collateralTokenId              121:153
          2   uint16  collateralWrapperContextLen    153:155

      Collateral Wrapper Context Data (M bytes)      155:---

      Node Receipts (48 * N bytes)
          N   NodeReceipts[] nodeReceipts
              16  uint128 tick
              16  uint128 used
              16  uint128 pending
    */

    /**************************************************************************/
    /* API */
    /**************************************************************************/

    /**
     * @dev Compute loan receipt hash
     * @param encodedReceipt Encoded loan receipt
     * @return Loan Receipt hash
     */
    function hash(bytes memory encodedReceipt) internal view returns (bytes32) {
        /* Take hash of chain ID (32 bytes) concatenated with encoded loan receipt */
        return keccak256(abi.encodePacked(block.chainid, encodedReceipt));
    }

    /**
     * @dev Encode a loan receipt into bytes
     * @param receipt Loan Receipt
     * @return Encoded loan receipt
     */
    function encode(LoanReceiptV1 memory receipt) internal pure returns (bytes memory) {
        /* Encode header */
        bytes memory header = abi.encodePacked(
            receipt.version,
            receipt.principal,
            receipt.repayment,
            receipt.borrower,
            receipt.maturity,
            receipt.duration,
            receipt.collateralToken,
            receipt.collateralTokenId,
            receipt.collateralWrapperContextLen,
            receipt.collateralWrapperContext
        );

        /* Encode node receipts */
        bytes memory nodeReceipts;
        for (uint256 i; i < receipt.nodeReceipts.length; i++) {
            nodeReceipts = abi.encodePacked(
                nodeReceipts,
                receipt.nodeReceipts[i].tick,
                receipt.nodeReceipts[i].used,
                receipt.nodeReceipts[i].pending
            );
        }

        return abi.encodePacked(header, nodeReceipts);
    }

    /**
     * @dev Decode a loan receipt from bytes
     * @param encodedReceipt Encoded loan Receipt
     * @return Decoded loan receipt
     */
    function decode(bytes calldata encodedReceipt) internal pure returns (LoanReceiptV1 memory) {
        /* Validate encoded receipt length */
        if (encodedReceipt.length < LOAN_RECEIPT_V1_HEADER_SIZE) revert InvalidReceiptEncoding();

        uint16 collateralWrapperContextLen = uint16(bytes2(encodedReceipt[153:155]));

        /* Validate length with collateral wrapper context */
        if (encodedReceipt.length < LOAN_RECEIPT_V1_HEADER_SIZE + collateralWrapperContextLen)
            revert InvalidReceiptEncoding();

        /* Validate length with node receipts */
        if (
            (encodedReceipt.length - LOAN_RECEIPT_V1_HEADER_SIZE - collateralWrapperContextLen) %
                LOAN_RECEIPT_V1_NODE_RECEIPT_SIZE !=
            0
        ) revert InvalidReceiptEncoding();

        /* Validate encoded receipt version */
        if (uint8(encodedReceipt[0]) != LOAN_RECEIPT_V1_VERSION) revert UnsupportedReceiptVersion();

        LoanReceiptV1 memory receipt;

        /* Decode header */
        receipt.version = uint8(encodedReceipt[0]);
        receipt.principal = uint256(bytes32(encodedReceipt[1:33]));
        receipt.repayment = uint256(bytes32(encodedReceipt[33:65]));
        receipt.borrower = address(uint160(bytes20(encodedReceipt[65:85])));
        receipt.maturity = uint64(bytes8(encodedReceipt[85:93]));
        receipt.duration = uint64(bytes8(encodedReceipt[93:101]));
        receipt.collateralToken = address(uint160(bytes20(encodedReceipt[101:121])));
        receipt.collateralTokenId = uint256(bytes32(encodedReceipt[121:153]));
        receipt.collateralWrapperContextLen = collateralWrapperContextLen;
        receipt.collateralWrapperContext = encodedReceipt[155:155 + collateralWrapperContextLen];

        /* Decode node receipts */
        uint256 numNodeReceipts = (encodedReceipt.length - LOAN_RECEIPT_V1_HEADER_SIZE - collateralWrapperContextLen) /
            LOAN_RECEIPT_V1_NODE_RECEIPT_SIZE;
        receipt.nodeReceipts = new NodeReceipt[](numNodeReceipts);
        for (uint256 i; i < numNodeReceipts; i++) {
            uint256 offset = LOAN_RECEIPT_V1_HEADER_SIZE +
                collateralWrapperContextLen +
                i *
                LOAN_RECEIPT_V1_NODE_RECEIPT_SIZE;
            receipt.nodeReceipts[i].tick = uint128(bytes16(encodedReceipt[offset:offset + 16]));
            receipt.nodeReceipts[i].used = uint128(bytes16(encodedReceipt[offset + 16:offset + 32]));
            receipt.nodeReceipts[i].pending = uint128(bytes16(encodedReceipt[offset + 32:offset + 48]));
        }

        return receipt;
    }
}
