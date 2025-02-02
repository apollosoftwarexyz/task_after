defmodule TaskAfterTest do
  use ExUnit.Case, async: true
  doctest TaskAfter

  test "TaskAfter and forget" do
    s = self()
    assert {:ok, _auto_id} = TaskAfter.task_after(500, fn -> send(s, 42) end)
    assert_receive(42, 600)
  end

  test "TaskAfter and receive" do
    assert {:ok, _auto_id} = TaskAfter.task_after(500, fn -> 42 end, send_result: self())
    assert_receive(42, 600)
  end

  test "TaskAfter with custom id" do
    assert {:ok, :my_id} =
             TaskAfter.task_after(500, fn -> 42 end, id: :my_id, send_result: self())

    assert_receive(42, 600)
  end

  test "TaskAfter with custom id duplicate fails" do
    assert {:ok, :dup_id} =
             TaskAfter.task_after(500, fn -> 42 end, id: :dup_id, send_result: self())

    assert {:error, {:duplicate_id, :dup_id}} =
             TaskAfter.task_after(500, fn -> 42 end, id: :dup_id, send_result: self())

    assert_receive(42, 600)
  end

  test "TaskAfter lots of tasks" do
    assert {:ok, _} = TaskAfter.task_after(400, fn -> 400 end, send_result: self())
    assert {:ok, _} = TaskAfter.task_after(200, fn -> 200 end, send_result: self())
    assert {:ok, _} = TaskAfter.task_after(500, fn -> 500 end, send_result: self())
    assert {:ok, _} = TaskAfter.task_after(100, fn -> 100 end, send_result: self())
    assert {:ok, _} = TaskAfter.task_after(300, fn -> 300 end, send_result: self())
    assert {:ok, _} = TaskAfter.task_after(600, fn -> 600 end, send_result: self())
    assert_receive(100, 150)
    assert_receive(200, 150)
    assert_receive(300, 150)
    assert_receive(400, 150)
    assert_receive(500, 150)
    assert_receive(600, 150)
  end

  test "TaskAfter non-global by name" do
    assert {:ok, pid} = TaskAfter.Worker.start_link(name: :testing_name)

    {:ok, _auto_id} =
      TaskAfter.task_after(500, fn -> 42 end, send_result: self(), name: :testing_name)

    assert_receive(42, 600)
    GenServer.stop(pid)
  end

  test "TaskAfter non-global by pid" do
    assert {:ok, pid} = TaskAfter.Worker.start_link()

    assert {:ok, _auto_id} =
             TaskAfter.task_after(500, fn -> 42 end, send_result: self(), pid: pid)

    assert_receive(42, 600)
    GenServer.stop(pid)
  end

  test "TaskAfter in process (unsafe, can freeze the task worker if the task does not return fast)" do
    assert {:ok, pid} = TaskAfter.Worker.start_link()
    s = self()

    assert {:ok, _auto_id} =
             TaskAfter.task_after(500, fn -> send(s, self()) end,
               send_result: :in_process,
               pid: pid
             )

    assert_receive(^pid, 600)
    GenServer.stop(pid)
  end

  test "TaskAfter and cancel timer, do not run the callback" do
    cb = fn -> 42 end
    assert {:ok, auto_id} = TaskAfter.task_after(500, cb)
    assert {:ok, ^cb} = TaskAfter.cancel_task_after(auto_id)
  end

  test "TaskAfter and cancel timer, but its already been run or does not exist" do
    assert {:error, {:does_not_exist, :none}} = TaskAfter.cancel_task_after(:none)
    assert {:ok, auto_id} = TaskAfter.task_after(0, fn -> 42 end, send_result: self())
    assert_receive(42, 100)
    assert {:error, {:does_not_exist, ^auto_id}} = TaskAfter.cancel_task_after(auto_id)
  end

  test "TaskAfter and cancel but also run the callback in process (unsafe again)" do
    assert {:ok, auto_id} = TaskAfter.task_after(500, fn -> 42 end)
    assert {:ok, 42} = TaskAfter.cancel_task_after(auto_id, run_result: :in_process)
  end

  test "TaskAfter and cancel but also run the callback async" do
    s = self()
    assert {:ok, auto_id} = TaskAfter.task_after(500, fn -> send(s, 42) end)
    assert {:ok, :task} = TaskAfter.cancel_task_after(auto_id, run_result: :async)
    assert_receive(42, 600)
  end

  test "TaskAfter and cancel but also run the callback async while returning result to pid" do
    s = self()
    assert {:ok, auto_id} = TaskAfter.task_after(500, fn -> 42 end)
    assert {:ok, :task} = TaskAfter.cancel_task_after(auto_id, run_result: s)
    assert_receive(42, 600)
  end

  test "TaskAfter and crash" do
    s = self()
    len = &length/1
    d = len.([])
    assert {:ok, _auto_id0} = TaskAfter.task_after(100, fn -> send(s, 21) end)
    assert {:ok, _auto_id1} = TaskAfter.task_after(250, fn -> send(s, 1 / d) end)
    assert {:ok, _auto_id2} = TaskAfter.task_after(500, fn -> send(s, 42) end)
    assert_receive(42, 600)
    assert_receive(21, 1)

    assert :no_message =
             (receive do
                m -> m
              after
                1 -> :no_message
              end)
  end

  test "TaskAfter and replace callback without recreate" do
    assert {:ok, auto_id} = TaskAfter.task_after(500, fn -> 1 end, send_result: self())
    assert {:ok, ^auto_id} = TaskAfter.change_task_after(auto_id, callback: fn -> 2 end)
    assert_receive(2, 600)

    assert {:error, {:does_not_exist, ^auto_id}} =
             TaskAfter.change_task_after(auto_id, callback: fn -> 3 end)
  end

  test "TaskAfter and replace callback and timeout with recreate" do
    assert {:ok, auto_id} = TaskAfter.task_after(500, fn -> 1 end, send_result: self())

    assert {:ok, ^auto_id} =
             TaskAfter.change_task_after(auto_id,
               recreate_if_necessary: true,
               timeout_after_ms: 500,
               send_result: self(),
               callback: fn -> 2 end
             )

    assert_receive(2, 600)

    assert {:ok, ^auto_id} =
             TaskAfter.change_task_after(auto_id,
               recreate_if_necessary: true,
               timeout_after_ms: 500,
               send_result: self(),
               callback: fn -> 3 end
             )

    assert_receive(3, 600)
  end

  test "TaskAfter and replace callback without timeout with recreate" do
    assert {:ok, auto_id} = TaskAfter.task_after(500, fn -> 1 end, send_result: self())

    assert {:ok, ^auto_id} =
             TaskAfter.change_task_after(auto_id,
               recreate_if_necessary: true,
               timeout_after_ms: 500,
               send_result: self(),
               callback: fn -> 2 end
             )

    assert_receive(2, 600)

    assert {:ok, ^auto_id} =
             TaskAfter.change_task_after(auto_id,
               recreate_if_necessary: true,
               timeout_after_ms: {:default, 500},
               send_result: self(),
               callback: fn -> 3 end
             )

    assert_receive(3, 600)
  end

  test "TaskAfter and replace timeout without recreate" do
    assert {:ok, auto_id} = TaskAfter.task_after(200, fn -> 1 end, send_result: self())
    assert {:ok, ^auto_id} = TaskAfter.change_task_after(auto_id, timeout_after_ms: 500)

    assert :no_message =
             (receive do
                m -> m
              after
                300 -> :no_message
              end)

    assert_receive(1, 600)
  end
end
