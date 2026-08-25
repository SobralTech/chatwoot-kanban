// Popover already paints the menu surface: background, blur, shadow, radius and
// border. Content that paints its own only lands a second, differently rounded
// card inside the first one, which is how this tree ended up with four looks for
// the same menu. What is left here is what Popover does not supply.
export const MENU_SURFACE_CLASSES = 'p-2 text-sm text-n-slate-12';

// Straight from components-next/dropdown-menu, so a kanban option row reads the
// same as every other dropdown row in the product.
export const MENU_OPTION_CLASSES =
  'inline-flex h-8 w-full min-w-0 items-center justify-start gap-2 rounded-lg px-2 py-1.5 text-left text-sm text-n-slate-12 transition-all duration-200 ease-in-out hover:bg-n-alpha-1 disabled:cursor-not-allowed disabled:opacity-50 dark:hover:bg-n-alpha-2';

export const MENU_OPTION_SELECTED_CLASSES =
  'bg-n-alpha-1 dark:bg-n-solid-active';

// MENU_OPTION_CLASSES already sets a text colour, and it wins on source order
// alone, so a row that means to recolour itself has to say so.
export const MENU_OPTION_DESTRUCTIVE_CLASSES = '!text-n-ruby-11';

// Separates sections inside one menu, matching the dropdown's own divider.
export const MENU_DIVIDER_CLASSES = 'mx-2 my-1 h-px bg-n-alpha-2';

// Shared by the bulk action bar and the menus it renders, so a trigger button
// looks the same whether or not it opens a popover.
export const BULK_ACTION_BUTTON_CLASSES =
  'inline-flex flex-shrink-0 items-center gap-1.5 whitespace-nowrap rounded-md px-2.5 py-1.5 text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50';
