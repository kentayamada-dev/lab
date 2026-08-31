"use client";

import { useEffect, useState } from "react";
import { createClient } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-web";
import { Todo, TodoService } from "../gen/todo/v1/todo_pb";

const client = createClient(
  TodoService,
  createConnectTransport({ baseUrl: "/rpc" }),
);

export default function Home() {
  const [todos, setTodos] = useState<Todo[]>([]);
  const [title, setTitle] = useState("");

  const load = async () => {
    const res = await client.listTodos({});
    setTodos(res.todos);
  };

  useEffect(() => {
    load();
  }, []);

  const add = async () => {
    if (!title) return;
    await client.createTodo({ title });
    setTitle("");
    await load();
  };

  const toggle = async (t: Todo) => {
    await client.updateTodo({ id: t.id, done: !t.done });
    await load();
  };

  return (
    <main style={{ maxWidth: 480, margin: "40px auto", fontFamily: "sans-serif" }}>
      <h1>Todo</h1>
      <div style={{ display: "flex", gap: 8 }}>
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="やること"
        />
        <button onClick={add}>追加</button>
      </div>
      <ul>
        {todos.map((t) => (
          <li key={String(t.id)} onClick={() => toggle(t)} style={{ cursor: "pointer" }}>
            {t.done ? "✅" : "⬜"} {t.title}
          </li>
        ))}
      </ul>
    </main>
  );
}
