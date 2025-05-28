// SPDX-License-Identifier: SimPL-2.0
pragma solidity >=0.8.x <0.9.0;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/iBounty.sol";
import "../utils/SafeMath.sol";
import "./ownership/Secondary.sol";
import "./FactoryStore.sol";
import "./BountyStore.sol";


//contract BountyFactory is Ownable {
contract BountyFactory is OwnableUpgradeable, UUPSUpgradeable {
    event Created(address founder, address bounty, Parameters paras);

    FactoryStore store;
    address public bountyBeacon;

    function initialize(address _bountyBeacon) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        bountyBeacon = _bountyBeacon;
        store = new FactoryStore();
    }

    // 获取逻辑地址
    function getImplementation() public view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    // UUPS升级授权函数，只有合约所有者能升级
    function _authorizeUpgrade(address) internal view override onlyOwner {}

    function createBounty(address _depositToken, uint256 _founderDepositAmount, uint256 _applicantDepositAmount, uint256 _applyDeadline) payable public {
        require(_applyDeadline > block.timestamp, "Applicant cutoff date is expired");
        Parameters memory paras = Parameters({depositToken: _depositToken,
        depositTokenIsNative: false,
        founderDepositAmount: _founderDepositAmount,
        applicantDepositMinAmount: _applicantDepositAmount,
        applyDeadline: _applyDeadline});
        bytes memory data = abi.encodeWithSelector(
            Bounty.initialize.selector,
            address(this),
            msg.sender
        );
        BountyProxy bounty = new BountyProxy(bountyBeacon, data);
        IBounty(address(bounty)).init(paras);
        // Bounty bounty = new Bounty(address(this), msg.sender);
        //bounty.init(paras);
        if (paras.founderDepositAmount > 0) {
            if (_depositToken == address(0)) {
                require(msg.value == paras.founderDepositAmount, "msg.value is not valid");
                // require(msg.sender.balance >= paras.founderDepositAmount, "Your balance is insufficient");
                (bool isSend,) = IBounty(address(bounty)).vaultAccount().call{value: paras.founderDepositAmount}("");
                require(isSend, "Transfer contract failure");
                paras.depositTokenIsNative = true;
            } else {
                IERC20 depositToken = IERC20(_depositToken);
                require(depositToken.balanceOf(msg.sender) >= _founderDepositAmount, "Deposit token balance is insufficient");
                require(depositToken.allowance(msg.sender, address(this)) >= _founderDepositAmount, "Deposit token allowance is insufficient");
                require(depositToken.transferFrom(msg.sender, IBounty(address(bounty)).vaultAccount(), _founderDepositAmount), "Deposit token transferFrom failure");
            }
        }
        IBounty(address(bounty)).transferOwnership(msg.sender);

        store.push(address(bounty));
        emit Created(msg.sender, address(bounty), paras);
    }

    function children() external view returns (address[] memory) {
        return store.children();
    }

    function isChild(address childAddr) external view returns (bool) {
        return store.isChild(childAddr);
    }

    function transferPrimary(address newFactory) external onlyOwner {
        store.transferPrimary(newFactory);
    }

    function getStore() external onlyOwner view returns (address) {
        return address(store);
    }

    function transferStore(address newStore) external onlyOwner {
        store = FactoryStore(newStore);
    }

    function renounceOwnership() public override onlyOwner {
    }
}

contract Bounty is IBounty, Initializable, OwnableUpgradeable {
//contract Bounty is Ownable, Initializable {
    using SafeMath for uint;

    enum BountyStatus {
        Pending, ReadyToWork, WorkStarted, Completed, Expired
    }
    enum ApplicantStatus {
        Pending, Applied, Refunded, Withdraw, Refused, Approved, Unapproved
    }
    enum Role {
        Pending, Founder, Applicant, Others
    }

    struct Applicant {
        uint256 depositAmount;
        ApplicantStatus status;
    }

    BountyStore store;
    IERC20 private depositToken;
    address private factory;
    address private founder;
    address private thisAccount;
    address payable private vault;
    Parameters private paras;
    uint256 private founderDepositAmount;
    uint256 private applicantDepositAmount;
    uint256 private timeLock;
    bool private depositLock;
    bool internal locked;
    BountyStatus private bountyStatus;
    uint256 public value;

    event Created(address owner, address factory, address founder, Parameters paras);
    event Deposit(address from, uint256 amount, uint256 founderBalance);
    event Close(address caller, BountyStatus bountyStatus);
    event Approve(address caller, address applicant);
    event Unapprove(address caller, address applicant);
    event Apply(address applicant, uint256 amount, uint256 balance, uint256 applicantsBalance);
    event ReleaseFounderDeposit(address founder, uint256 amount, uint256 balance);
    event ReleaseApplicantDeposit(address applicant, uint256 amount, uint256 balance, uint256 applicantsBalance);
    event Lock(address caller);
    event Unlock(address caller);
    event PostUpdate(address caller, uint256 expiredTime);

    modifier onlyFounder() {
        _checkFounder();
        _;
    }

    modifier onlyOthers() {
        _checkOthers();
        _;
    }

    modifier onlyApplied() {
        _checkAppliedApplicant();
        _;
    }

    modifier inApplyTime() {
        _checkInApplyTime();
        _;
    }

    modifier inReadyToWork() {
        _checkBountyStatus(BountyStatus.ReadyToWork, "Bounty status not in ready to work");
        _;
    }

    modifier inWorkStarted() {
        _checkBountyStatus(BountyStatus.WorkStarted, "Bounty status not in work started");
        _;
    }

    modifier notCompleted() {
        _checkNotBountyStatus(BountyStatus.Completed, "Bounty status is completed");
        _;
    }

    modifier notExpired() {
        _checkNotBountyStatus(BountyStatus.Expired, "Bounty status is expired");
        _;
    }

    modifier depositLocked() {
        require(depositLock, "Deposit is unlock");
        _;
    }

    modifier depositUnlock() {
        require(!depositLock, "Deposit is locked");
        _;
    }

    modifier zeroDeposit() {
        require((founderDepositAmount+applicantDepositAmount) == 0, "Deposit balance more than zero");
        _;
    }

    modifier nonzeroDeposit() {
        require((founderDepositAmount+applicantDepositAmount) > 0, "Deposit amount is zero");
        _;
    }

    modifier depositLocker() {
        _checkDepositLocker(msg.sender);
        _;
    }

    modifier depositUnlocker() {
        _checkDepositUnlocker(msg.sender);
        _;
    }

    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    modifier zeroStore() {
        require(address(store) == address(0), "Store is not zero");
        _;
    }

/*
    constructor(address _factory, address _founder) Ownable(_founder) {
        factory = _factory;
        founder = _founder;
        thisAccount = address(this);
    }
*/
    function initialize(address _factory, address _founder) public initializer {
        __Ownable_init(_founder);
        factory = _factory;
        founder = _founder;
        thisAccount = address(this);
    }

    // 因为factory里面有调这个函数，所以在iBounty里声明了，但是这样就和OwnableUpgradeable多继承了，所以需要override一下
    function transferOwnership(address newOwner) public override(OwnableUpgradeable, IBounty) {
        // 这里可以编写你自己的转移所有权逻辑，也可以调用父合约的实现
        super.transferOwnership(newOwner);
    }

    function incrementValue() public {
        value++;
    }

    function init(Parameters memory _paras) public payable onlyOwner zeroStore {
        store = new BountyStore();
        vault = payable(address(store));

        paras = _paras;
        bountyStatus = _statusFromTime();
        founderDepositAmount = paras.founderDepositAmount;
        depositLock = false;
        timeLock = 0;
        if (paras.depositToken == address(0)) {
            paras.depositTokenIsNative = true;
        } else {
            paras.depositTokenIsNative = false;
            depositToken = IERC20(paras.depositToken);
        }
        emit Created(owner(), factory, founder, paras);
    }

    function deposit(uint256 _amount) public payable onlyFounder inReadyToWork {
        require(_amount > 0, "Deposit amount is zero");
        _deposit(_amount);
        founderDepositAmount = founderDepositAmount.add(_amount);
        emit Deposit(msg.sender, _amount, founderDepositAmount);
    }

    function release() public payable onlyFounder depositUnlock nonzeroDeposit {
        _releaseAllDeposit();
    }

    function close() public payable onlyFounder zeroDeposit notCompleted notExpired {
        require(_refundDepositToken(payable(founder), _getBalance(vault)), "Transfer balance to the founder failure");
        bountyStatus = BountyStatus.Completed;
        emit Close(msg.sender, bountyStatus);
    }

    function approveApplicant(address _address) public onlyFounder inReadyToWork {
        (,,bool _isAppliedApplicant,) = _applicantState(_address);
        require(_isAppliedApplicant || (!_isAppliedApplicant && paras.applicantDepositMinAmount == 0),
            "To be approved must a applicant");

        _refuseOtherApplicants(_address);
        _addApplicant(_address, 0, ApplicantStatus.Approved);
        bountyStatus = BountyStatus.WorkStarted;
        depositLock = true;
        store.putDepositLocker(_address, true);
        store.putDepositUnlocker(_address, true);
        _startTimer();
        emit Approve(msg.sender, _address);
    }

    function unapproveApplicant(address _address) public onlyFounder inWorkStarted {
        (,bool _isApprovedApplicant,,) = _applicantState(_address);
        require(_isApprovedApplicant, "Applicant status is not approved");
        store.putApplicantStatus(_address, uint8(ApplicantStatus.Unapproved));
        store.putDepositLocker(_address, false);
        emit Unapprove(msg.sender, _address);
    }

    function applyFor(uint256 _amount) public payable onlyOthers inApplyTime inReadyToWork noReentrant {
        require(_amount >= paras.applicantDepositMinAmount, "Deposit amount less than limit");
        _deposit(_amount);
        _addApplicant(msg.sender, _amount, ApplicantStatus.Applied);
        applicantDepositAmount = applicantDepositAmount.add(_amount);
        (uint256 _depositAmount,) = store.getApplicant(msg.sender);
        emit Apply(msg.sender, _amount, _depositAmount, applicantDepositAmount);
    }

    function releaseMyDeposit() public payable onlyApplied depositUnlock inReadyToWork noReentrant {
        _refundApplicant(msg.sender);
        store.putApplicantStatus(msg.sender, uint8(ApplicantStatus.Withdraw));
    }

    function lock() public payable depositLocker depositUnlock {
        depositLock = true;
        emit Lock(msg.sender);
    }

    function unlock() public payable depositUnlocker depositLocked {
        depositLock = false;
        emit Unlock(msg.sender);
    }

    function postUpdate() public depositLocker inWorkStarted {
        _startTimer();
        emit PostUpdate(msg.sender, timeLock);
    }

    function vaultAccount() public view onlyOwner returns (address) {
        return vault;
    }

    function state() public view returns (uint8 _bountyStatus, uint _applicantCount, uint256 _depositBalance,
        uint256 _founderDepositAmount, uint256 _applicantDepositAmount,
        uint256 _applicantDepositMinAmount, bool _depositLock,
        uint256 _timeLock, uint8 _myRole, uint256 _myDepositAmount, uint8 _myStatus) {

        (uint8 _role, uint256 _depositAmount, uint8 _status) = whoAmI();
        address[] memory _applicants = store.applicants();

        return (uint8(bountyStatus), _applicants.length, _getBalance(vault), founderDepositAmount, applicantDepositAmount,
        paras.applicantDepositMinAmount, depositLock, timeLock, _role, _depositAmount, _status);
    }

    function whoAmI() public view returns (uint8 _role, uint256 _depositAmount, uint8 _applicantStatus) {
        return _whoIs(msg.sender);
    }

    function parameters() public view returns (Parameters memory _paras) {
        return paras;
    }

    function transferPrimary(address newBounty) external onlyOwner {
        store.transferPrimary(newBounty);
    }

    function getStore() external onlyOwner view returns (address) {
        return address(store);
    }

    function transferStore(address payable newStore) external onlyOwner {
        store = BountyStore(newStore);
    }

    function renounceOwnership() public override onlyOwner {
    }

    function _depositIsLocked() internal view returns (bool) {
        if (timeLock == 0 || block.timestamp < timeLock) {
            return depositLock;
        } else {
            return false;
        }
    }

    function _deposit(uint256 _amount) internal {
        if (_amount > 0) {
            if (paras.depositTokenIsNative) {
                require(msg.value == _amount, "msg.value is not valid");
                // require(msg.sender.balance >= _amount, "Your balance is insufficient");
                (bool isSend,) = vault.call{value: _amount}("");
                require(isSend, "Transfer contract failure");
            } else {
                require(depositToken.allowance(msg.sender, thisAccount) >= _amount, "Your deposit token allowance is insufficient");
                require(depositToken.balanceOf(msg.sender) >= _amount, "Your deposit token balance is insufficient");
                require(depositToken.transferFrom(msg.sender, vault, _amount), "Deposit token transferFrom failure");
            }
        }
    }

    function _releaseAllDeposit() internal {
        _refundFounder();
        _refundApplicants();
    }

    function _refuseOtherApplicants(address _address) internal {
        address[] memory _applicants = store.applicants();
        for (uint i=0;i<_applicants.length;i++) {
            if (address(_applicants[i]) != address(_address)) {
                _refundApplicant(_applicants[i]);
                store.putApplicantStatus(_applicants[i], uint8(ApplicantStatus.Refused));
            }
        }
    }

    function _refundFounder() internal {
        uint256 _amount = founderDepositAmount;
        require(_refundDepositToken(payable(founder), _amount), "Refund deposit to the founder failure");
        founderDepositAmount = 0;
        emit ReleaseFounderDeposit(msg.sender, _amount, founderDepositAmount);
    }

    function _refundApplicants() internal {
        address[] memory _applicants = store.applicants();
        for (uint i=0;i<_applicants.length;i++) {
            address _address = _applicants[i];
            _refundApplicant(_address);
            (,uint8 _status) = store.getApplicant(_address);
            if (_status == uint8(ApplicantStatus.Applied)) {
                store.putApplicantStatus(_address, uint8(ApplicantStatus.Refunded));
            }
        }
    }

    function _refundApplicant(address _address) internal {
        (uint256 _amount,) = store.getApplicant(_address);
        require(_refundDepositToken(payable(_address), _amount), "Refund deposit to applicant failure");
        applicantDepositAmount = applicantDepositAmount.sub(_amount);
        store.putApplicantAmount(_address, 0);
        emit ReleaseApplicantDeposit(_address, _amount, 0, applicantDepositAmount);
    }

    function _refundDepositToken(address payable _to, uint256 _amount) internal returns (bool) {
        bool isSend = true;
        if (_amount > 0) {
            isSend = false;
            if (paras.depositTokenIsNative) {
                isSend = store.transfer(_to, _amount);
            } else {
                isSend = store.transferToken(depositToken, _to, _amount);
            }
            require(isSend, "Refund failure");
        }
        return isSend;
    }

    function _addApplicant(address _address, uint256 _amount, ApplicantStatus _status) internal {
        (bool _isApplicant,,) = _getApplicant(_address);
        if (!_isApplicant) {
            store.pushApplicant(_address);
        }
        (uint256 _mapAmount,) = store.getApplicant(_address);
        store.putApplicant(_address, _mapAmount.add(_amount), uint8(_status));
    }

    function _getBalance(address _address) internal view returns (uint256) {
        if (paras.depositTokenIsNative) {
            return _address.balance;
        } else {
            return depositToken.balanceOf(_address);
        }
    }

    function _startTimer() internal {
        timeLock = block.timestamp + 5 days;
    }

    function _statusFromTime() internal view returns (BountyStatus) {
        if (block.timestamp < paras.applyDeadline) {
            return BountyStatus.ReadyToWork;
        } else {
            return BountyStatus.Expired;
        }
    }

    function _checkDepositLocker(address _address) internal view virtual {
        bool _isLocker = false;
        if (store.getDepositLocker(_address)) {
            if (timeLock == 0 || (timeLock > 0 && block.timestamp <= timeLock)) {
                _isLocker = true;
            }
        }
        require(_isLocker, "Caller is not allowed to lock");
    }

    function _checkDepositUnlocker(address _address) internal view virtual {
        bool _isUnlocker = false;
        if (store.getDepositUnlocker(_address)) {
            if (timeLock == 0 || (timeLock > 0 && block.timestamp <= timeLock)) {
                _isUnlocker = true;
            }
        } else if (timeLock > 0 && block.timestamp > timeLock && _address == founder) {
            _isUnlocker = true;
        }
        require(_isUnlocker, "Caller is not allowed to unlock");
    }

    function _checkFounder() internal view virtual {
        require(msg.sender == founder, "Caller is not the founder");
    }

    function _checkOthers() internal view virtual {
        require(msg.sender != factory, "Must not be factory");
        require(msg.sender != founder, "Must not be founder");
        require(msg.sender != thisAccount, "Must not be contractself");
        (bool _isApplicant,,uint8 _status) = _getApplicant(msg.sender);
        require((!_isApplicant)||(_isApplicant&&_status==uint8(ApplicantStatus.Withdraw)), "Must not be applicant");
    }

    function _checkAppliedApplicant() internal view virtual {
        (,,bool _isAppliedApplicant,) = _applicantState(msg.sender);
        require(_isAppliedApplicant, "Please apply first");
    }

    function _checkInApplyTime() internal view virtual {
        require(block.timestamp <= paras.applyDeadline, "Time past the application deadline");
    }

    function _checkBountyStatus(BountyStatus _status, string memory _errorMessage) internal view {
        require(bountyStatus == _status, _errorMessage);
    }

    function _checkNotBountyStatus(BountyStatus _status, string memory _errorMessage) internal view {
        require(bountyStatus != _status, _errorMessage);
    }

    function _applicantState(address _address) internal view returns (bool _isApplicant, bool _isApprovedApplicant,
        bool _isAppliedApplicant, uint256 _depositAmount) {
        (bool _isOrNot, uint256 _amount, uint8 _status) = _getApplicant(_address);
        _isApplicant = _isOrNot;
        _isApprovedApplicant = false;
        _isAppliedApplicant = false;
        if (_isApplicant) {
            if (_status == uint8(ApplicantStatus.Approved)) {
                _isApprovedApplicant = true;
            } else if (_status == uint8(ApplicantStatus.Applied)) {
                _isAppliedApplicant = true;
            }
        }
        _depositAmount = _amount;
    }

    function _whoIs(address _address) internal view returns (uint8, uint256, uint8) {
        uint8 _role = uint8(Role.Others);
        (bool _isApplicant, uint256 _depositAmount, uint8 _status) = _getApplicant(_address);
        if (_isApplicant) {
            _role = uint8(Role.Applicant);
        } else if (_address == founder) {
            _role = uint8(Role.Founder);
            _depositAmount = founderDepositAmount;
        }
        return (_role, _depositAmount, _status);
    }

    function _getApplicant(address _address) internal view returns (bool, uint256, uint8) {
        bool _isApplicant = true;
        (uint256 _amount, uint8 _status) = store.getApplicant(_address);
        if (_amount == 0 && _status == 0) {
            _isApplicant = false;
        }
        return (_isApplicant, _amount, _status);
    }
}

contract BountyProxy is BeaconProxy {
    constructor(address _beacon, bytes memory _data) BeaconProxy(_beacon, _data) {}
}

contract BountyBeacon is Initializable, OwnableUpgradeable, IBeacon {
    address public implemAddr;

    function initialize(address _implementation) public initializer {
        __Ownable_init(msg.sender);
        implemAddr = _implementation;
    }

    function implementation() external view override returns (address) {
        return implemAddr;
    }

    function upgradeTo(address newImplementation) public onlyOwner {
        implemAddr = newImplementation;
    }
}
