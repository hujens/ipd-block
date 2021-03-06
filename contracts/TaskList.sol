pragma solidity ^0.5.11;
pragma experimental ABIEncoderV2;

import './PPCToken.sol';

contract TaskList {

	/*
	------------	DATA & TYPES   ------------
	*/

	uint public task_count = 0;
	enum State { created, accepted, completed, validated }
	// TODO: add an "initiated" state in which validators can add validators and
	//       workers before workers can accept the task
	uint8 ppc_threshold = 90; // PPC threshold for the workers to get the PPCToken
	uint public hourly_rate = 1 ether; // the hourly rate is fixed and the same for all workers

	// enum Difficulty { standard, advanced , expert }
	// enum Uncertainity { clear, uncertain, unknown }
	PPCToken private ppctoken;

	constructor (address _ppctoken_address) public {
		ppctoken = PPCToken(_ppctoken_address);
	}

	struct Task {
		uint id;
		string title;
		string description;
		State state;
		uint deadline;
		uint8 Qrating;
		uint8 ppc;
		uint8 ppc_worker;
		mapping(address => bool) validators_map;
		address payable[] validators;
		mapping(address => Validation) validations;
		mapping(address => bool) workers_map;
		address payable[] workers;
		mapping(address => uint) worked_hours;
		mapping(address => bool) acceptations;
		mapping(address => Completion) completions;
		uint balance;
		//uint predecessor_id;
		//uint successor_id;
	}

	mapping(uint => Task) public tasks;

	// represents the validation and its ratings of one validator
	struct Validation {
		bool exists;
		uint8 ppc;
		uint8 Qrating;
	}

	// represents the completion and its ratings of one worker
	struct Completion {
		bool exists;
		uint8 ppc;
	}

	/*
	------------	EVENTS    ------------
	*/

	event TaskCreated(
		uint id,
		string title,
		State state,
		address payable[] validators
	);

	event TaskState(
		uint id,
		State state
	);

	event validatorAdded(
		uint task_id,
		address validator
	);

	event workerAdded(
		uint task_id,
		address worker
	);

	event workedHoursAdded(
		uint task_id,
		address worker,
		uint _hours
	);

	event taskFunded(
		uint task_id,
		address sender,
		uint256 amount
	);

	event PPCTokenMinted(
		address account,
		uint amount
	);

	/*
	------------	MODIFIERS    ------------
	*/

	modifier validatorsOnly(uint _task_id) {
		// checks that the sender is a validator of task
		require(tasks[_task_id].validators_map[msg.sender], "Caller is not a validator of this task");
		_;
	}

	modifier workersOnly(uint _task_id, address _account) {
		require(tasks[_task_id].workers_map[_account], "Worker is not assigned to this task");
		_;
	}

	/*
	------------	FUNCTIONS    ------------
	*/

	function createTask(string memory _title, string memory _description) public {
		uint _id = task_count;
		Task memory task = Task({
			id: _id,
			title: _title,
			description: _description,
			state: State.created,
			deadline: 0,
			Qrating: 0,
			ppc: 0,
			ppc_worker: 0,
			validators: new address payable[](0),
			workers: new address payable[](0),
			balance: 0
		});
		// https://medium.com/loom-network/ethereum-solidity-memory-vs-storage-how-to-initialize-an-array-inside-a-struct-184baf6aa2eb
		tasks[_id] = task;
		task_count++;
		tasks[_id].validators.push(msg.sender);
		tasks[_id].validators_map[msg.sender] = true;
		emit TaskCreated(_id, _title, State.created, tasks[_id].validators);
	}

	// TODO: add removeTask function requiring approvals from all validators and workers

	// add a validator to the given task
	function addValidator(uint _task_id, address payable _validator) public validatorsOnly(_task_id) {
		require(!tasks[_task_id].workers_map[_validator], "Worker cannot be validator");
		Task storage _task = tasks[_task_id];
		_task.validators.push(_validator);
		_task.validators_map[_validator] = true;
		emit validatorAdded(_task_id, _validator);
	}

	// returns the array of validators of the given task
	function getValidators(uint _task_id) public view returns (address payable[] memory) {
		return tasks[_task_id].validators;
	}

	// add a worker to the given task
	function addWorker(uint _task_id, address payable _worker) public validatorsOnly(_task_id) {
		require(!tasks[_task_id].validators_map[_worker], "Validator cannot be worker");
		Task storage _task = tasks[_task_id];
		_task.workers.push(_worker);
		_task.workers_map[_worker] = true;
		_task.worked_hours[_worker] = 0;
		emit workerAdded(_task_id, _worker);
	}

	// returns the array of workers of the given task
	function getWorkers(uint _task_id) public view returns (address payable[] memory) {
		return tasks[_task_id].workers;
	}

	// accept task for worker calling the function
	function acceptTask(uint _task_id) public workersOnly(_task_id, msg.sender) {
		Task storage _task = tasks[_task_id];

		if(_task.state == State.created){
			_task.acceptations[msg.sender] = true;
			bool accepted = false;

			// go through every worker's acceptation
			for(uint16 i = 0; i < _task.workers.length; i++) {
				accepted = _task.acceptations[_task.workers[i]];
			}
			// accept the task if all workers have accepted it;
			if(accepted){
				_task.state = State.accepted;
			}
		}
	}

	// adds worked hours in the given task to the worker calling the function
	function addWorkedHours(uint _task_id, uint _hours) public workersOnly(_task_id, msg.sender) {
		Task storage _task = tasks[_task_id];
		if(_task.state == State.accepted){
			_task.worked_hours[msg.sender] += _hours;
			emit workedHoursAdded(_task_id, msg.sender, _hours);
		}
	}

	// returns the worked hours of the given worker in the given task
	function getWorkedHours(uint _task_id, address _worker) public view returns (uint) {
		return tasks[_task_id].worked_hours[_worker];
	}

	// stores funds allocated to the given task in this contract
	function fundTask(uint _task_id) public payable {
		// stores funds for the given task in this smart contract
		// the code bellow is just used to keep track of how much funds are allocated to each task
		// the actual ethers are automatically stored in the contract just by implementing this payable function
		Task storage _task = tasks[_task_id];
		_task.balance += msg.value;
		emit taskFunded(_task_id, msg.sender, msg.value);
	}

	// completes the task for the worker calling the function
	function completeTask(uint _task_id, uint8 _ppc) public workersOnly(_task_id, msg.sender) returns (bool) {
		Task storage _task = tasks[_task_id];

		if(_task.state == State.accepted && 0 < _ppc && _ppc <= 100){
			Completion storage _completion = _task.completions[msg.sender];
			_completion.ppc = _ppc;
			_completion.exists = true;

			return computeCompletion(_task_id);
		}
		return false;
	}

	// returns the completion ratings for the given worker
	function getCompletion(uint _task_id, address _worker) public view returns (Completion memory) {
		return tasks[_task_id].completions[_worker];
	}

	// calculates the mean ratings values from all workers
	// completes the task if conditions are met
	// return true if the task is completed
	function computeCompletion(uint _task_id) internal returns (bool) {
		Task storage _task = tasks[_task_id];
		uint8 n = 0;
		uint8 n_workers = uint8(_task.workers.length);
		uint8 _ppc = 0;

		for(uint8 i = 0; i < n_workers; i++){
			address payable _worker = _task.workers[i];
			Completion storage _completion = _task.completions[_worker];

			if(_completion.exists){
				_ppc += _completion.ppc;
				n++;
			}
		}

		// for the task to be completed:
		// - each worker's approval is required
		if(n == n_workers){
			_task.ppc_worker = _ppc / n;
			_task.state = State.completed;
		}

		return _task.state == State.completed;
	}

	// returns the amout of fund required to pay all worked hours of the given task
	function neededTaskFund(uint _task_id) public view returns (uint) {
		Task storage _task = tasks[_task_id];
		uint amount;
		for(uint16 i = 0; i < _task.workers.length; i++) {
			address payable _worker = _task.workers[i];
			amount += _task.worked_hours[_worker];
		}
		return amount * hourly_rate;
	}

	// return true if the funds allocated to the task and saved in the contract are sufficient to pay the workers
	function sufficientFunds(uint _task_id) public view returns (bool) {
		Task memory _task = tasks[_task_id];
		return _task.balance >= neededTaskFund(_task_id);
	}

	// called from each individual validator to set his ratings
	// return the result from computeValidation or false if the task was not completed before
	function validateTask(uint _task_id, uint8 _ppc, uint8 _Qrating) public validatorsOnly(_task_id) returns (bool) {
		Task storage _task = tasks[_task_id];

		// a validator can only set his ratings if the task was completed before
		if(_task.state == State.completed && 0 < _ppc && _ppc <= 100 && 0 < _Qrating && _Qrating <= 10){
			Validation storage _validation = _task.validations[msg.sender];
			_validation.ppc = _ppc;
			_validation.Qrating = _Qrating;
			_validation.exists = true;

			return computeValidation(_task_id);
		}
		return false;
	}

	// returns the validation ratings for the given validator
	function getValidation(uint _task_id, address _validator) public view returns (Validation memory) {
		return tasks[_task_id].validations[_validator];
	}

	// calculates the mean ratings values from all validators
	// validates the task and perform payments if conditions are met
	// return true if the task is validated
	function computeValidation(uint _task_id) internal returns (bool) {
		Task storage _task = tasks[_task_id];
		uint8 n = 0;
		uint8 n_validators = uint8(_task.validators.length);
		uint8 _ppc = 0;
		uint8 _Qrating = 0;

		for(uint8 i = 0; i < n_validators; i++){
			address payable _validator = _task.validators[i];
			Validation storage _validation = _task.validations[_validator];

			if(_validation.exists){
				_ppc += _validation.ppc;
				_Qrating += _validation.Qrating;
				n++;
			}
		}

		// for the task to be validated:
		// - mean ppc from validators has to be greater than the workers' one
		// - each validator's approval is required
		// - funds have to be sufficient
		if(_ppc > 0 && _ppc >= _task.ppc_worker && n == n_validators && sufficientFunds(_task_id)){
			_task.ppc = _ppc / n;

			if(_Qrating > 0){
				_task.Qrating = _Qrating / n;
			}
			_task.state = State.validated;

			// payments
			releasePayment(_task_id);
			mintPPCTOken(_task_id);
		}

		return _task.state == State.validated;
	}

	// send payments to the workers and return the rest to the payers
	function releasePayment(uint _task_id) internal {
		Task storage _task = tasks[_task_id];
		for(uint16 i = 0; i < _task.workers.length; i++) {
			address payable _worker = _task.workers[i];
			uint amount = _task.worked_hours[_worker] * hourly_rate;
			_task.balance -= amount;
			_worker.transfer(amount);
		}
		uint rest = _task.balance;
		_task.balance -= rest;
		_task.validators[0].transfer(rest); // return the rest to the validator[0]
		// TODO: keep track of which address funded which amount in a mapping
	}

	// mints PPCTokens for every worker of the task if the ppc threshold is respected
	function mintPPCTOken(uint _task_id) internal {
		Task memory _task = tasks[_task_id];
		if(_task.ppc >= ppc_threshold) {
			for(uint16 i = 0; i < _task.workers.length; i++) {
				address _worker = _task.workers[i];
				ppctoken.mint(_worker, 1);
				emit PPCTokenMinted(_worker, 1);
			}
		}
	}

	// returns the amount of ether stored in this contract
	function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }
}