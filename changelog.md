##13th June 2024
-> Cleanup Models,
-> Cleanup API extensions and models,
-> Reorganise file pattern
-> Add Font assets,
-> Add Splash screen,
-> Add Device Preview,

##14th June 2024
-> Add Localization,
-> Add Typography,

##15th June 2025
-> add: country picker and dropdown
-> add: live event and completed event
-> add: comprehensive settings system with dark mode support
-> add: board settings with color picker and piece styles
-> add: language settings with multi-language support
-> add: timezone settings with UTC offset selection
-> add: notifications preferences with granular controls
-> add: persistent settings storage using SharedPreferences
-> fix: responsive design for all settings screens
-> fix: language settings dialog type safety issues
-> add: search bar functionality

##16th June 2025
-> update: replaced icons in hamburger menu with SVG assets
-> update: improved analysis board menu item appearance
-> fix: consistent icon sizing in hamburger menu
-> update: semantic labels added to SVG assets for accessibility
-> add: apple signin button added
-> fix: standardized height of premium item to match other menu items
-> fix: the search bar was made according to the design

##17th June 2025
-> star and three dots png fixed
-> fix: vertical alignment of star and three dots icons in event cards
-> update: restructured EventCard widget for improved layout consistency
-> finalized search bar
-> filter widget added with design accuracy
-> board color added
-> player card and list screen

#18th June
-> Configure Supabase,
-> Add Apple and google Sign in Methods,
-> upcoming events card
-> add: reusable segmented switcher widget with customizable styling
-> added the segmented switchbar
-> added the tournament screen
-> player screen
-> favourites screen
-> refactored player, tournaments, favourite screens

#19 June
-> calendar screen added
-> standings screen added
-> tournament details screen
-> design accuracy and refactoring
-> refine Tournament Screen,
-> add Bottom Navigation View,
-> add animations for button click,
-> add country picker overlay screen,
-> add library screen UI,

#20 June
-> Fix the Alert and Modal flow for settings,
-> Add Tournament Details Screen,
-> Create Models for Tournament, Game and Round based on schema,
-> Setup Repository and API for Tournament, Game and Round,

#21 June
-> Connect Tournament screen with Supabase,
-> Connect Favorite with local repository,
-> Connect Filter option and search to supabase,
-> Create models for repository and Layout Data parsing and conversion for Tour,
-> Cleanup Twisted widgets,

#22 June
-> Connect Tournament Details with Selected Tournament,
-> Create new view model for Tournament Details,
-> Add Url Launcher for Tournament Website,

#23 June
-> Games Screen added,
-> background blur during popup,
-> dismissable popup when clicked anywhere except the popup,
-> settings completed with saving the selected options in local storage,

#24 june
-> hamburger cleanup
-> players screen and favourite screen added
-> premium screen added
-> search functionality in players and favourites screen

#25 june
-> Update android package name and label, [ com.chessever.app ]
-> Update bundle identifier to [ com.chessever.app  ],
-> Add release config,
-> chessboard
-> moves' PGN on chessboard
-> demo chessboard with hardcoded pgn added

#26 june
-> board color update with the selection from board settings
-> custom board icons
-> simulating PGN moves

#27 june
-> refactor chessboard logic
-> Add new bottom nav bar in board view
-> Add app bar in board view,
-> replace custom board icons with .png

#28 june
-> Fix AppIcon Setting using AppIcon,
-> Update Splash Screen Functionality

#29 june
-> Add ResponseHelper for Widget and Font Responsiveness,
-> Add skeletonizer for animation,


#30 june
-> Local repository logic for Tournament, 
-> Skeleton Widgets across the app for
-> loading, Implement pull to refresh,
-> Local Repository for Games,
-> Filter with Round data


#1 July
-> implement animation searchbar and add search functionality,
-> Update pull to refresh functionality for re-populating data for games,
-> add responsive helper in tournament_details and missing screens,
-> add new icons across appbars,


#2 July
-> Setup Local Notification configuration in Android and IOS,
-> save selected country in local Storages,
-> update menu dropdown at look like the design,
-> Search feature only search from those filtered tournament from calendarTourView,
-> Create Calendar Detail Screen with appropriate Month and Year Filtering,
-> Update Tournament Card with countrymen detail,
-> Add responsive helper in calendar screen for accurate size,
-> Create an internal testing in Play store and deploy a new build,
-> add new icons across appbars,

#3 july
->. Update GamesTourScreen to include a 3 dot option that opens a pop-up blurring the background
-> Update GamesAppBarWidget to include a top 3 dot option that opens a pop-up menu with options
-> Minor design update in hamburger menu  and Premium button , update gradient
-> BackDropFilterWidget for blur

#4 july
-> Display the countryman icon in the tournaments
-> show the fen data in the view with chess board, update the view model with fromGames first to include fen data in the view model

#6 july
->Fix the pin option dialog position in the screen in Games Screen and make it easily clickable
-> Change 3 dots of Games screen from the design
-> Create Premium Dialog and delete the old premium screen,