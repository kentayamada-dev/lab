"use client";

import { useCallback, useEffect, useState } from "react";
import { Code, ConnectError } from "@connectrpc/connect";
import { Todo } from "@/gen/todo/v1/todo_pb";
import { AuthForm } from "./auth-form";
import { authClient, todoClient } from "./client";
import { AccountClosed, DeleteAccount } from "./delete-account";
import { buttonClass, errorClass, inputClass } from "./ui";

export default function Home() {
  const [signedIn, setSignedIn] = useState<boolean | null>(null);
  // When the account this page closed stops existing, and null whenever no
  // account was closed here. It outlives the session it was read through, the
  // closing having ended that, so it is held above the signed-in state rather
  // than inside it.
  const [purgeAt, setPurgeAt] = useState<Date | null>(null);

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

  // Logging out is an RPC because only the server can expire an HttpOnly
  // cookie, and because the session the token names has to be closed there too
  // (api/internal/auth/service.go). The failure is passed on rather than
  // swallowed: the session is still open after one, and a page showing itself
  // signed out of a session the API goes on serving would be undone by the
  // next reload.
  const signOut = useCallback(async () => {
    await authClient.logOut({});
    setSignedIn(false);
  }, []);

  // An expired session is already gone, so going back to the form is all there
  // is to do about it and there is nothing to ask the server for.
  const forgetSession = useCallback(() => setSignedIn(false), []);

  // Closing the account ended every session it had, this one included, so the
  // page is signed out by the same answer that tells it when the data goes.
  const closed = useCallback((at: Date) => {
    setPurgeAt(at);
    setSignedIn(false);
  }, []);

  if (purgeAt) {
    return <AccountClosed purgeAt={purgeAt} onDone={() => setPurgeAt(null)} />;
  }
  if (signedIn === null) return null;
  if (!signedIn) return <AuthForm onAuthenticated={() => setSignedIn(true)} />;

  return <Todos onSignOut={signOut} onSessionExpired={forgetSession} onClosed={closed} />;
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

function Todos({
  onSignOut,
  onSessionExpired,
  onClosed,
}: {
  onSignOut: () => Promise<void>;
  onSessionExpired: () => void;
  onClosed: (purgeAt: Date) => void;
}) {
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
        onSessionExpired();
        return;
      }
      setError(errorMessage(code));
    },
    [onSessionExpired],
  );

  // The first read of the list, and the only one: ListTodos answers one page at
  // a time, so walk the tokens to the end.
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

  // Each mutation answers with the row it changed, so the list is kept in step
  // from that answer. Reading it back instead would walk every page again for
  // one changed row, which is the whole list on every click.
  const run = async (call: () => Promise<void>) => {
    try {
      await call();
      setError("");
    } catch (err) {
      report(err);
    }
  };

  // An answer that carries no todo leaves the list alone: showing one row less
  // than there is would be worse than showing it stale until the next load.
  const replaceTodo = (updated?: Todo) =>
    setTodos((todos) => (updated ? todos.map((t) => (t.id === updated.id ? updated : t)) : todos));

  // The title is trimmed here as well as by the API, so that a box holding
  // only spaces is the same nothing an empty one is rather than a request that
  // comes back as an error.
  const add = async () => {
    const next = title.trim();
    if (!next) return;
    await run(async () => {
      const { todo } = await todoClient.createTodo({ title: next });
      // ListTodos orders by id and a new todo has the highest one, so it
      // belongs at the end.
      setTodos((todos) => (todo ? [...todos, todo] : todos));
    });
    setTitle("");
  };

  const toggle = (t: Todo) =>
    run(async () => {
      const { todo } = await todoClient.updateTodo({ id: t.id, done: !t.done });
      replaceTodo(todo);
    });

  const rename = async (t: Todo) => {
    const next = editTitle.trim();
    if (!next) return;
    await run(async () => {
      const { todo } = await todoClient.updateTodo({ id: t.id, title: next });
      replaceTodo(todo);
    });
    setEditingId(null);
  };

  const remove = (t: Todo) =>
    run(async () => {
      await todoClient.deleteTodo({ id: t.id });
      setTodos((todos) => todos.filter((other) => other.id !== t.id));
    });

  return (
    <main className="mx-auto w-full max-w-lg px-4 py-10">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold">Todo</h1>
        <button className={buttonClass} type="button" onClick={() => run(onSignOut)}>
          ログアウト
        </button>
      </div>

      <form
        className="flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          add();
        }}
      >
        <input
          className={`${inputClass} flex-1`}
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="やること"
        />
        <button className={buttonClass} type="submit">
          追加
        </button>
      </form>
      {error && <p className={`${errorClass} mt-3`}>{error}</p>}

      <ul className="mt-6 flex flex-col gap-2">
        {todos.map((t) => (
          <li key={String(t.id)} className="flex items-center gap-2">
            {editingId === t.id ? (
              <>
                <input
                  className={`${inputClass} flex-1`}
                  value={editTitle}
                  onChange={(e) => setEditTitle(e.target.value)}
                  autoFocus
                />
                <button className={buttonClass} type="button" onClick={() => rename(t)}>
                  保存
                </button>
                <button className={buttonClass} type="button" onClick={() => setEditingId(null)}>
                  やめる
                </button>
              </>
            ) : (
              <>
                <button
                  className="flex-1 cursor-pointer text-left text-sm"
                  type="button"
                  onClick={() => toggle(t)}
                >
                  <span className={t.done ? "line-through opacity-60" : undefined}>
                    {t.done ? "✅" : "⬜"} {t.title}
                  </span>
                </button>
                <button
                  className={buttonClass}
                  type="button"
                  onClick={() => {
                    setEditingId(t.id);
                    setEditTitle(t.title);
                  }}
                >
                  編集
                </button>
                <button className={buttonClass} type="button" onClick={() => remove(t)}>
                  削除
                </button>
              </>
            )}
          </li>
        ))}
      </ul>

      {/* Last and apart, so that closing the account is not one slip away from
          the buttons that act on a single todo. */}
      <hr className="my-8 border-zinc-200 dark:border-zinc-800" />
      <DeleteAccount onClosed={onClosed} />
    </main>
  );
}
