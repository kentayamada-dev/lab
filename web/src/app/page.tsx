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
  const [editingId, setEditingId] = useState<bigint | null>(null);
  const [editTitle, setEditTitle] = useState("");

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

  const rename = async (t: Todo) => {
    if (!editTitle.trim()) return;
    await client.updateTodo({ id: t.id, title: editTitle });
    setEditingId(null);
    await load();
  };

  const remove = async (t: Todo) => {
    await client.deleteTodo({ id: t.id });
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
          <li key={String(t.id)} style={{ display: "flex", gap: 8, alignItems: "center" }}>
            {editingId === t.id ? (
              <>
                <input
                  value={editTitle}
                  onChange={(e) => setEditTitle(e.target.value)}
                />
                <button onClick={() => rename(t)}>保存</button>
                <button onClick={() => setEditingId(null)}>キャンセル</button>
              </>
            ) : (
              <>
                <span onClick={() => toggle(t)} style={{ cursor: "pointer" }}>
                  {t.done ? "✅" : "⬜"} {t.title}
                </span>
                <button
                  onClick={() => {
                    setEditingId(t.id);
                    setEditTitle(t.title);
                  }}
                >
                  編集
                </button>
                <button onClick={() => remove(t)}>削除</button>
              </>
            )}
          </li>
        ))}
      </ul>
    </main>
  );
}
