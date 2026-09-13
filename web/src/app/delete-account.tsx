"use client";

import { useState } from "react";
import { Code, ConnectError } from "@connectrpc/connect";
import { timestampDate } from "@bufbuild/protobuf/wkt";
import { accountClient } from "./client";
import { buttonClass, dangerButtonClass, errorClass, inputClass } from "./ui";

// What a failed closing tells the reader. Unauthenticated is the wrong
// password rather than an expired session: reaching the procedure at all took
// a session the server accepted, and it is the password it asks for again
// (api/internal/account/service.go).
function errorMessage(code: Code): string {
  switch (code) {
    case Code.Unauthenticated:
      return "パスワードが違います";
    default:
      return "通信に失敗しました。しばらくしてからお試しください";
  }
}

// The button stays behind a confirmation step that asks for the password,
// which is the API's requirement and not the page's: what the step adds is
// telling the reader what they are about to spend before they spend it.
export function DeleteAccount({ onClosed }: { onClosed: (purgeAt: Date) => void }) {
  const [asking, setAsking] = useState(false);
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const cancel = () => {
    setAsking(false);
    setPassword("");
    setError("");
  };

  const submit = async () => {
    setBusy(true);
    setError("");
    try {
      const { purgeAt } = await accountClient.deleteAccount({ password });
      // The instant is what the server recorded, so the page states the
      // promise the API made rather than one of its own. An answer without one
      // is a server that changed shape, and there is nothing to show for it.
      onClosed(purgeAt ? timestampDate(purgeAt) : new Date());
    } catch (err) {
      setError(errorMessage(ConnectError.from(err).code));
    } finally {
      setBusy(false);
    }
  };

  if (!asking) {
    return (
      <button className={dangerButtonClass} type="button" onClick={() => setAsking(true)}>
        退会する
      </button>
    );
  }

  return (
    <form
      className="flex flex-col gap-2"
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
    >
      <p className="text-sm">
        退会すると、登録したすべての todo が見られなくなり、ログインもできなくなります。確認のためパスワードを入力してください。
      </p>
      <input
        className={inputClass}
        type="password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        placeholder="パスワード"
        autoComplete="current-password"
        required
      />
      <div className="flex gap-2">
        <button className={dangerButtonClass} type="submit" disabled={busy}>
          退会する
        </button>
        <button className={buttonClass} type="button" onClick={cancel} disabled={busy}>
          やめる
        </button>
      </div>
      {error && <p className={errorClass}>{error}</p>}
    </form>
  );
}

// What is left to say once the account is closed. The session ended with it,
// so there is nothing to go back to but the login form.
export function AccountClosed({ purgeAt, onDone }: { purgeAt: Date; onDone: () => void }) {
  return (
    <main className="mx-auto w-full max-w-md px-4 py-10">
      <h1 className="mb-4 text-xl font-semibold">退会しました</h1>
      <p className="mb-6 text-sm">
        {purgeAt.toLocaleDateString("ja-JP")} までは、問い合わせればアカウントを元に戻せます。それ以降はデータごと削除され、元に戻せません。
      </p>
      <button className={buttonClass} type="button" onClick={onDone}>
        最初の画面に戻る
      </button>
    </main>
  );
}
