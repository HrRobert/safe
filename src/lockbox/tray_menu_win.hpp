/*
  Lockbox: Encrypted File System
  Copyright (C) 2013 Rian Hunter <rian@alum.mit.edu>

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License as published by
  the Free Software Foundation, either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>
 */

#ifndef __lockbox_windows_menu_hpp
#define __lockbox_windows_menu_hpp

#include <lockbox/util.hpp>

#include <lockbox/tray_menu.hpp>
#include <lockbox/windows_error.hpp>
#include <lockbox/windows_menu.hpp>

namespace lockbox { namespace win {

struct DestroyMenuDestroyer {
  void operator()(HMENU a) {
    auto ret = DestroyMenu(a);
    if (!ret) throw std::runtime_error("couldn't free!");
  }
};

typedef lockbox::ManagedResource<HMENU, DestroyMenuDestroyer> ManagedMenuHandle;

class TrayMenu;

class TrayMenuItem {
private:
  ManagedMenuHandle _parent_mh;
  HMENU _mh;
  int _item_idx;

  HMENU _get_mh() { return _mh; }

  TrayMenuItem(ManagedMenuHandle parent_mh,
               HMENU mh,
               int item_idx)
    : _parent_mh(std::move(parent_mh))
    , _mh(std::move(mh))
    , _item_idx(std::move(item_idx)) {}

public:
  bool
  set_tooltip(std::string tooltip) {
    // we don't support menu tooltips
    (void) tooltip;
    return false;
  }

  bool
  set_property(lockbox::TrayMenuProperty name, std::string value) {
    // we don't support any properties
    (void) name;
    (void) value;
    return false;
  }

  void
  disable() {
    // NB: EnableMenuItem with MF_DISABLED doesn't seem to work on
    // Wine-1.6.1 on Mac OS X 10.9, i686-w64-mingw32-g++ (GCC) 4.9.0 20130531 (experimental)
    // use SetMenuItemInfo() instead

    MENUITEMINFOW mif;
    lockbox::zero_object(mif);

    mif.cbSize = sizeof(mif);
    mif.fMask = MIIM_STATE;
    mif.fState = MFS_GRAYED;

    auto success = SetMenuItemInfo(_get_mh(), _item_idx, TRUE, &mif);
    if (!success) throw w32util::windows_error();
  }

  friend class TrayMenu;
};

class TrayMenu {
private:
  ManagedMenuHandle _parent_mh;
  HMENU _mh;

  HMENU _get_mh() { return _mh; }

  TrayMenu(ManagedMenuHandle parent_mh, HMENU mh)
  : _parent_mh(std::move(parent_mh))
  , _mh(std::move(mh)) {}

public:
  TrayMenu(ManagedMenuHandle parent_mh) : TrayMenu(parent_mh, parent_mh.get()) {}

  TrayMenuItem
  append_item(std::string title,
              lockbox::TrayMenuAction action,
              lockbox::tray_menu_action_arg_t action_arg = 0) {
    const int item_idx =
      w32util::menu_append_string_item(_get_mh(), false, title,
                                       lockbox::encode_menu_id<UINT>(action, action_arg));
    // give the item a reference to the parent_mh to keep us in scope
    return TrayMenuItem(_parent_mh, _mh, item_idx);
  }

  void
  append_separator() {
    return w32util::menu_append_separator(_get_mh());
  }

  TrayMenu
  append_menu(std::string title) {
    auto item_idx = w32util::menu_append_string_item(_get_mh(), false, title, 0);

    auto sub_menu = CreateMenu();
    if (!sub_menu) throw w32util::windows_error();

    MENUITEMINFOW mif;
    lockbox::zero_object(mif);

    mif.cbSize = sizeof(mif);
    mif.fMask = MIIM_SUBMENU;
    mif.hSubMenu = sub_menu;

    auto success = SetMenuItemInfo(_get_mh(), item_idx, TRUE, &mif);
    if (!success) {
      auto success = DestroyMenu(sub_menu);
      if (!success) lbx_log_error("Failure to destroy sub_menu, leaking...");
      throw w32util::windows_error();
    }

    // give the submenu a reference to the parent_mh to keep us in scope
    return TrayMenu(_parent_mh, sub_menu);
  }
};

}}

#endif