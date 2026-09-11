"use client";

import { useCallback, useEffect, useState } from "react";
import { Code, ConnectError } from "@connectrpc/connect";
import { Todo } from "../gen/todo/v1/todo_pb";
import { AuthForm } from "./auth-form";
import { authClient, todoClient } from "./client";

export default function Home() {
  const [signedIn, setSignedIn] = useState<boolean | null>(null);

  // The session cookie is HttpOnly, so there is nothing here to read: whether
  // one is in place can only be learnt by making a request with it. The
  // smallest page there is answers that, and Todos loads properly afterwards.
  useEffect(() => {
    todoClient
      .listTodos({ pageSize: 1 })
      .then(() => setSignedIn(true))
      // Any other failure is left to Todos, which has somewhere to show it.
      .catch((err) => setSignedIn(ConnectError.from(err).code !== Code.Unauthenticated));
  }, []);

  // Logging out is an RPC because expiring an HttpOnly cookie is something
  // only the server can do; the local state follows either way, since a client
  // giving up its session should not be stuck with it because the call failed.
  const signOut = useCallback(async () => {
    try {
      await authClient.logOut({});
    } finally {
      setSignedIn(false);
    }
  }, []);

  if (signedIn === null) return null;
  if (!signedIn) return <AuthForm onAuthenticated={() => setSignedIn(true)} />;

  return <Todos onSignedOut={signOut} />;
}

// What a failed todo call tells the reader. Unauthenticated is missing on
// purpose: report handles it by going back to the form instead of showing it.
function errorMessage(code: Code): string {
  switch (code) {
    case Code.InvalidArgument:
      return "やることは 1〜1000 文字で入力してください";
    case Code.NotFound:
      return "その項目は見つかりませんでした";
    default:
      return "通信に失敗しました。しばらくしてからお試しください";
  }
}

function Todos({ onSignedOut }: { onSignedOut: () => void | Promise<void> }) {
  const [todos, setTodos] = useState<Todo[]>([]);
  const [title, setTitle] = useState("");
  const [editingId, setEditingId] = useState<bigint | null>(null);
  const [editTitle, setEditTitle] = useState("");
  const [error, setError] = useState("");

  // An expired or withdrawn session is the one failure the page can act on by
  // itself: it goes back to asking for the credentials. The rest is worded
  // here rather than taken from the answer, for the reason auth-form.tsx gives.
  const report = useCallback(
    (err: unknown) => {
      const { code } = ConnectError.from(err);
      if (code === Code.Unauthenticated) {
        onSignedOut();
        return;
      }
      setError(errorMessage(code));
    },
    [onSignedOut],
  );

  // ListTodos answers one page at a time, so walk the tokens to the end.
  const load = useCallback(async () => {
    try {
      const all: Todo[] = [];
      let pageToken = "";
      do {
        const res = await todoClient.listTodos({ pageToken });
        all.push(...res.todos);
        pageToken = res.nextPageToken;
      } while (pageToken);
      setTodos(all);
      setError("");
    } catch (err) {
      report(err);
    }
  }, [report]);

  useEffect(() => {
    load();
  }, [load]);

  const run = async (call: () => Promise<unknown>) => {
    try {
      await call();
      await load();
    } catch (err) {
      report(err);
    }
  };

  const add = async () => {
    if (!title) return;
    await run(() => todoClient.createTodo({ title }));
    setTitle("");
  };

  const toggle = (t: Todo) => run(() => todoClient.updateTodo({ id: t.id, done: !t.done }));

  const rename = async (t: Todo) => {
    if (!editTitle.trim()) return;
    await run(() => todoClient.updateTodo({ id: t.id, title: editTitle }));
    setEditingId(null);
  };

  const remove = (t: Todo) => run(() => todoClient.deleteTodo({ id: t.id }));

  return (
    <main style={{ maxWidth: 480, margin: "40px auto", fontFamily: "sans-serif" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h1>Todo</h1>
        <button onClick={() => void onSignedOut()}>ログアウト</button>
      </div>
      <div style={{ display: "flex", gap: 8 }}>
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="やること"
        />
        <button onClick={add}>追加</button>
      </div>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
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
