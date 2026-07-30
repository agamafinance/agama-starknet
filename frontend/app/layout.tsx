import "./globals.css";
import type { ReactNode } from "react";

export const metadata = {
  title: "Agama on Starknet",
  description: "Private-credit lending on Starknet, with native STRK20 privacy.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
