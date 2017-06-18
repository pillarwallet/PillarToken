pragma solidity ^0.4.11;


import "./zeppelin/ownership/Multisig.sol";
import "./zeppelin/ownership/Shareable.sol";
import "./zeppelin/DayLimit.sol";
import "./zeppelin/SafeMath.sol";

contract PillarFutureSaleWallet is Multisig, Shareable, DayLimit {
  using SafeMath for uint;

  uint lockPeriod;
  struct Transaction {
     address to;
     uint value;
     bytes data;
   }

   /**
    * Constructor, sets the owners addresses, number of approvals required, and daily spending limit
    * @param _owners A list of owners.
    * @param _required The amount required for a transaction to be approved.
    */
   function PillarFutureSaleWallet(address[] _owners, uint _required, uint _daylimit)
     Shareable(_owners, _required)
     DayLimit(_daylimit) {
       lockPeriod = now.add(3 years);
     }

   /**
    * @dev destroys the contract sending everything to `_to`.
    */
   function destroy(address _to) onlymanyowners(keccak256(msg.data)) external {
     selfdestruct(_to);
   }

   /**
    * @dev Fallback function, receives value and emits a deposit event.
    */
   function() payable {
     // just being sent some cash?
     if (msg.value > 0)
       Deposit(msg.sender, msg.value);
   }

   /**
    * @dev Outside-visible transaction entry point. Executes transaction immediately if below daily
    * spending limit. If not, goes into multisig process. We provide a hash on return to allow the
    * sender to provide shortcuts for the other confirmations (allowing them to avoid replicating
    * the _to, _value, and _data arguments). They still get the option of using them if they want,
    * anyways.
    * @param _to The receiver address
    * @param _value The value to send
    * @param _data The data part of the transaction
    */
   function execute(address _to, uint _value, bytes _data) external onlyOwner returns (bytes32 _r) {

     if(now < lockPeriod) throw;

     // first, take the opportunity to check that we're under the daily limit.
     if (underLimit(_value)) {
       SingleTransact(msg.sender, _value, _to, _data);
       // yes - just execute the call.
       if (!_to.call.value(_value)(_data)) {
         throw;
       }
       return 0;
     }
     // determine our operation hash.
     _r = keccak256(msg.data, block.number);
     if (!confirm(_r) && txs[_r].to == 0) {
       txs[_r].to = _to;
       txs[_r].value = _value;
       txs[_r].data = _data;
       ConfirmationNeeded(_r, msg.sender, _value, _to, _data);
     }
   }

   /**
    * @dev Confirm a transaction by providing just the hash. We use the previous transactions map,
    * txs, in order to determine the body of the transaction from the hash provided.
    * @param _h The transaction hash to approve.
    */
   function confirm(bytes32 _h) onlymanyowners(_h) returns (bool) {
     if (txs[_h].to != 0) {
       if (!txs[_h].to.call.value(txs[_h].value)(txs[_h].data)) {
         throw;
       }
       MultiTransact(msg.sender, _h, txs[_h].value, txs[_h].to, txs[_h].data);
       delete txs[_h];
       return true;
     }
   }

   /**
    * @dev Updates the daily limit value.
    * @param _newLimit  Uint to represent the new limit.
    */
   function setDailyLimit(uint _newLimit) onlymanyowners(keccak256(msg.data)) external {
     _setDailyLimit(_newLimit);
   }

   /**
    * @dev Resets the value spent to enable more spending
    */
   function resetSpentToday() onlymanyowners(keccak256(msg.data)) external {
     _resetSpentToday();
   }


   // INTERNAL METHODS
   /**
    * @dev Clears the list of transactions pending approval.
    */
   function clearPending() internal {
     uint length = pendingsIndex.length;
     for (uint i = 0; i < length; ++i) {
       delete txs[pendingsIndex[i]];
     }
     super.clearPending();
   }


   // FIELDS

   // pending transactions we have at present.
   mapping (bytes32 => Transaction) txs;
 }