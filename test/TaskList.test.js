// @ts-nocheck
const PPCToken = artifacts.require('./PPCToken.sol')
const TaskList = artifacts.require('./TaskList.sol')

const truffleAssert = require('truffle-assertions');

contract('TaskList Tests', (accounts) => {

  const validator_0 = accounts[0];
  const validator_1 = accounts[1];
  const worker_1 = accounts[2];
  const worker_hours_1 = 2;
  const worker_hours_2 = 3;
  const worker_2 = accounts[3];
  const task_id = 1;

  before(async () => {
    this.ppctoken = await PPCToken.deployed()
    this.tasklist = await TaskList.deployed()
  })

  it('deploys successfully', async () => {
    const address = await this.tasklist.address
    assert.notEqual(address, 0x0)
    assert.notEqual(address, '')
    assert.notEqual(address, null)
    assert.notEqual(address, undefined)
  })

  it('creates tasks', async () => {
    const result = await this.tasklist.createTask('A new task', "description");
    const task = await this.tasklist.tasks(task_id);
    assert.equal(task.title, 'A new task');

    const task_count = await this.tasklist.task_count();
    assert.equal(task_count.toNumber(), 1 + task_id);

    let validators = await this.tasklist.getValidators(task_id);
    assert.equal(validators[0], accounts[0]);

    // check the event
    const event = result.logs[0].args
    assert.equal(event.id.toNumber(), task_id)
    assert.equal(event.title, 'A new task')
    assert.equal(event.state.toNumber(), 0)
    assert.equal(event.validators[0], accounts[0])
  });

  it('adds validator from the allowed accounts', async () => {
    // validator adds new validator
    let result_1 = await this.tasklist.addValidator(task_id, validator_1, {from: validator_0});

    truffleAssert.eventEmitted(result_1, 'validatorAdded', (ev) => {
      return ev.task_id == task_id && ev.validator == validator_1;
    });

    let validators = await this.tasklist.getValidators(task_id);
    assert.equal(validators[1], validator_1);
  });

  it('worker tries to add a validator, which is not permitted', async () => {
    truffleAssert.reverts(
      this.tasklist.addValidator(task_id, worker_2, {from: worker_1}), 
      "Caller is not a validator of this task"
    );
  });

  it('adds worker from the allowed accounts', async () => {
    // validator adds new worker
    let result_1 = await this.tasklist.addWorker(task_id, worker_1, {from: validator_1});
    truffleAssert.eventEmitted(result_1, 'workerAdded', (ev) => {
      return ev.task_id == task_id && ev.worker == worker_1;
    });
    let workers = await this.tasklist.getWorkers(task_id);
    assert.equal(workers[0], workers[0]);
  });

  it('worker tries to add a worker, which is not permitted', async () => {
    truffleAssert.reverts(
      this.tasklist.addWorker(task_id, worker_2, {from: worker_1}), 
      "Caller is not a validator of this task"
    );
  });

  it('adds a validator as worker, which is not permitted', async () => {
    truffleAssert.reverts(
      this.tasklist.addWorker(task_id, validator_0, {from: validator_0}),
      "Validator cannot be worker"
    );
  });

  it('adds worked hours', async () => {
    let result = await this.tasklist.addWorkedHours(task_id, worker_hours_1, {from: worker_1});
    truffleAssert.eventEmitted(
      result, 'workedHoursAdded', (ev) => {
      return ev.task_id == task_id && ev.worker == worker_1 && ev._hours == worker_hours_1
    });
    let hours = await this.tasklist.getWorkedHours(task_id, worker_1);
    assert.equal(hours, worker_hours_1)
  });

  it('non-worker tries to add worked hours, which is not permitted', async () => {
    truffleAssert.reverts(
      this.tasklist.addWorkedHours(task_id, 2, {from: validator_0}),
      "Worker is not assigned to this task"
    )
  });

  it('funds task', async () => {
    const amount = web3.utils.toWei('10', "ether");
    const balance_before = await web3.eth.getBalance(validator_1);
    let result = await this.tasklist.fundTask(task_id, {from: validator_1, value: amount, gasPrice:0});

    // check account balance
    const balance_after = await web3.eth.getBalance(validator_1);
    let value = Number(balance_before) - Number(balance_after);
    assert.equal(value, amount);

    // check deposited amount
    let contract_balance = await this.tasklist.getContractBalance();
    let task = await this.tasklist.tasks(task_id);
    let task_balance = await task.balance;
    assert.equal(contract_balance, amount, task_balance);
  });

  it('completes task', async () => {
    await this.tasklist.completeTask(task_id, 100, {from: worker_1});
    let task = await this.tasklist.tasks(task_id);
    assert.equal(task.ppc_worker, 100);
    assert.equal(task.state, 2);
  });

  it('validates task and mints PPCToken', async () => {
    await this.tasklist.addWorker(task_id, worker_2, {from: validator_1});
    await this.tasklist.addWorkedHours(task_id, worker_hours_2, {from: worker_2});

    let is_minter = await this.ppctoken.isMinter(this.tasklist.address);
    assert.isTrue(is_minter);
    let ppc_balance_before = await this.ppctoken.balanceOf(worker_1);
    let contract_balance_before = await this.tasklist.getContractBalance();

    await this.tasklist.validateTask(task_id, 100, 10, {from: validator_0});

    let task = await this.tasklist.tasks(task_id);
    assert.equal(task.ppc, 100);
    assert.equal(task.state, 3);
    assert.equal(task.Qrating, 10)

    // check account balance
    let ppc_balance_after = await this.ppctoken.balanceOf(worker_1);
    let ppc_diff = Number(ppc_balance_after) - Number(ppc_balance_before);
    assert.equal(ppc_diff, 1);

    let contract_balance_after = await this.tasklist.getContractBalance();
    let ether_diff = Number(contract_balance_before) - Number(contract_balance_after);
    const salary = await this.tasklist.salary();
    assert.equal(ether_diff, salary * (worker_hours_1 + worker_hours_2));
  });

  /*
  it('toggles task started', async () => {
    const task_id = 1
    const result = await this.tasklist.toggleStarted(task_id) // starts the task

    // check the task
    const task = await this.tasklist.tasks(task_id)
    assert.equal(task.state.toNumber(), 1) // checks task state

    // check the event
    const event = result.logs[0].args
    assert.equal(event.id.toNumber(), task_id) // checks event task id
    assert.equal(event.state.toNumber(), 1) // check event task state
  })
  */
})