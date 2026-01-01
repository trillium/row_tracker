"use client";

import { Fragment, useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { HiSun, HiMoon, HiComputerDesktop } from "react-icons/hi2";
import {
  Menu,
  MenuButton,
  MenuItem,
  MenuItems,
  Radio,
  RadioGroup,
  Transition,
} from "@headlessui/react";

const Blank = () => <div className="h-6 w-6" />;

const ThemeSwitch = () => {
  const [mounted, setMounted] = useState(false);
  const { theme, setTheme, resolvedTheme } = useTheme();

  // When mounted on client, now we can show the UI
  useEffect(() => {
    // Use queueMicrotask to avoid cascading renders
    queueMicrotask(() => setMounted(true));
  }, []);

  return (
    <div className="mr-5 flex items-center">
      <Menu as="div" className="relative inline-block text-left">
        <div className="hover:text-primary-500 dark:hover:text-primary-400 flex items-center justify-center">
          <MenuButton aria-label="Theme switcher">
            {mounted ? (
              resolvedTheme === "dark" ? (
                <HiMoon className="h-6 w-6" />
              ) : (
                <HiSun className="h-6 w-6" />
              )
            ) : (
              <Blank />
            )}
          </MenuButton>
        </div>
        <Transition
          as={Fragment}
          enter="transition ease-out duration-100"
          enterFrom="transform opacity-0 scale-95"
          enterTo="transform opacity-100 scale-100"
          leave="transition ease-in duration-75"
          leaveFrom="transform opacity-100 scale-100"
          leaveTo="transform opacity-0 scale-95"
        >
          <MenuItems className="theme-menu ring-opacity-5 absolute right-0 z-50 mt-2 w-32 origin-top-right divide-y divide-gray-100 rounded-md bg-white shadow-lg ring-1 ring-black focus:outline-hidden dark:bg-gray-800">
            <RadioGroup value={theme} onChange={setTheme}>
              <div className="p-1">
                <Radio value="light">
                  <MenuItem>
                    {({ focus }) => (
                      <button
                        className={`${
                          focus ? "bg-primary-600 text-white" : ""
                        } group flex w-full items-center rounded-md px-2 py-2 text-sm`}
                      >
                        <HiSun className="mr-2 h-6 w-6" />
                        Light
                      </button>
                    )}
                  </MenuItem>
                </Radio>
                <Radio value="dark">
                  <MenuItem>
                    {({ focus }) => (
                      <button
                        className={`${
                          focus ? "bg-primary-600 text-white" : ""
                        } group flex w-full items-center rounded-md px-2 py-2 text-sm`}
                      >
                        <HiMoon className="mr-2 h-6 w-6" />
                        Dark
                      </button>
                    )}
                  </MenuItem>
                </Radio>
                <Radio value="system">
                  <MenuItem>
                    {({ focus }) => (
                      <button
                        className={`${
                          focus ? "bg-primary-600 text-white" : ""
                        } group flex w-full items-center rounded-md px-2 py-2 text-sm`}
                      >
                        <HiComputerDesktop className="mr-2 h-6 w-6" />
                        System
                      </button>
                    )}
                  </MenuItem>
                </Radio>
              </div>
            </RadioGroup>
          </MenuItems>
        </Transition>
      </Menu>
    </div>
  );
};

export default ThemeSwitch;
