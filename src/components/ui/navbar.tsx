import Link from "next/link";

export default function Navbar() {
  return (
    <div className="w-screen flex items-center justify-center">
      <nav className="max-w-screen-lg flex flex-grow space-between items-center justify-between p-4">
        <Link href="/" className="text-white hover:text-gray-300">
          Home
        </Link>
        <ul className="flex justify-end space-between w-full space-x-4">
          <li>
            <Link
              href="/while_rowing"
              className="text-white hover:text-gray-300"
            >
              While Rowing
            </Link>
          </li>
        </ul>
      </nav>
    </div>
  );
}
