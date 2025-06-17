import 'package:flutter/material.dart';
import 'tournament_details_screen.dart';

class TournamentListScreen extends StatefulWidget {
  const TournamentListScreen({Key? key}) : super(key: key);

  @override
  State<TournamentListScreen> createState() => _TournamentListScreenState();
}

class _TournamentListScreenState extends State<TournamentListScreen> {
  String filterResultValue = 'All Results';
  String filterColorValue = 'All Colors';

  final Set<int> favoritedTournaments = {};

  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> tournaments = [
    {
      'name': 'Norway Chess 2025',
      'status': 'LIVE',
      'date': 'Feb 27 -29, 2025',
      'country': 'Netherlands',
      'players': 12,
      'elo': 2714,
      'participants': ['Magnus Carlsen', 'Fabiano Caruana', 'Alireza Firouzja'],
      'results': {
        'Magnus Carlsen': {'color': 'Black', 'result': 'Wins'},
        'Fabiano Caruana': {'color': 'White', 'result': 'Losses'},
        'Alireza Firouzja': {'color': 'White', 'result': 'Draws'},
      },
    },
    {
      'name': 'World Rapid Championship 2025',
      'status': 'LIVE',
      'date': 'Dec 10 - 12, 2025',
      'country': 'Russia',
      'players': 16,
      'elo': 2700,
      'participants': ['Ian Nepomniachtchi', 'Hikaru Nakamura', 'Magnus Carlsen'],
      'results': {
        'Ian Nepomniachtchi': {'color': 'Black', 'result': 'Draws'},
        'Hikaru Nakamura': {'color': 'White', 'result': 'Wins'},
        'Magnus Carlsen': {'color': 'Black', 'result': 'Losses'},
      },
    },
    {
      'name': 'FIDE Grand Prix 2025',
      'status': 'LIVE',
      'date': 'Mar 5 - 15, 2025',
      'country': 'Germany',
      'players': 14,
      'elo': 2695,
      'participants': ['Ding Liren', 'Levon Aronian', 'Wesley So'],
      'results': {
        'Ding Liren': {'color': 'White', 'result': 'Wins'},
        'Levon Aronian': {'color': 'Black', 'result': 'Losses'},
        'Wesley So': {'color': 'White', 'result': 'Draws'},
      },
    },
    {
      'name': 'Candidates Tournament 2026',
      'status': 'Completed',
      'date': 'Apr 18 - May 6, 2025',
      'country': 'Spain',
      'players': 8,
      'elo': 2720,
      'participants': ['Anish Giri', 'Teimour Radjabov', 'Fabiano Caruana'],
      'results': {
        'Anish Giri': {'color': 'Black', 'result': 'Wins'},
        'Teimour Radjabov': {'color': 'White', 'result': 'Draws'},
        'Fabiano Caruana': {'color': 'Black', 'result': 'Losses'},
      },
    },
    {
      'name': 'London Chess Classic 2025',
      'status': 'Completed',
      'date': 'Nov 1 - 8, 2025',
      'country': 'UK',
      'players': 10,
      'elo': 2705,
      'participants': ['Vishy Anand', 'Vladimir Kramnik', 'Hikaru Nakamura'],
      'results': {
        'Vishy Anand': {'color': 'White', 'result': 'Wins'},
        'Vladimir Kramnik': {'color': 'Black', 'result': 'Draws'},
        'Hikaru Nakamura': {'color': 'White', 'result': 'Losses'},
      },
    },
    {
      'name': 'Magnus Carlsen Invitational 2025',
      'status': 'Completed',
      'date': 'Jul 15 - 20, 2025',
      'country': 'Norway',
      'players': 8,
      'elo': 2702,
      'participants': ['Magnus Carlsen', 'Wesley So', 'Levon Aronian'],
      'results': {
        'Magnus Carlsen': {'color': 'White', 'result': 'Wins'},
        'Wesley So': {'color': 'Black', 'result': 'Draws'},
        'Levon Aronian': {'color': 'White', 'result': 'Losses'},
      },
    },
  ];

  String _searchQuery = '';
  int _selectedTab = 0;
  bool _isUpcomingHovered = false;
  bool _isAllEventsHovered = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Filtering logic: search first, then filter by color/result if set
  List<Map<String, dynamic>> get filteredTournaments {
    // Only filter by player name (search box)
    String playerQuery = _searchQuery.toLowerCase();
    if (playerQuery.isEmpty) {
      return List<Map<String, dynamic>>.from(tournaments);
    }
    return tournaments.where((t) {
      final participants = (t['participants'] as List<String>);
      return participants.any((p) => p.toLowerCase().contains(playerQuery));
    }).toList();
  }

  Widget _buildUpcomingEventsList() {
    final now = DateTime.now();
    // Build a list of tuples: (tournament, daysAway)
    final List<Map<String, dynamic>> upcomingWithDays = [];
    for (final t in tournaments) {
      final status = t['status'] as String;
      if (status == 'LIVE') continue;
      final dateStr = t['date'] as String;
      // Parse the end date (assume last date in the string is the end)
      final dateRangeMatch = RegExp(r'(\w+\s*\d{1,2})\s*-\s*(\w+)?\s*(\d{1,2}),\s*(\d{4})').firstMatch(dateStr);
      DateTime? startDate;
      DateTime? endDate;
      if (dateRangeMatch != null) {
        // e.g. 'Nov 1 - 8, 2025' or 'Jul 15 - 20, 2025'
        final startMonthStr = dateRangeMatch.group(1)!;
        final endMonthStr = dateRangeMatch.group(2);
        final startDay = int.tryParse(RegExp(r'\d+').firstMatch(startMonthStr)?.group(0) ?? '') ?? 1;
        final startMonth = _monthStringToInt(startMonthStr.split(' ')[0]);
        final endDay = int.tryParse(dateRangeMatch.group(3) ?? '') ?? startDay;
        final year = int.tryParse(dateRangeMatch.group(4) ?? '') ?? now.year;
        startDate = DateTime(year, startMonth ?? 1, startDay);
        final endMonth = endMonthStr != null && endMonthStr.isNotEmpty ? _monthStringToInt(endMonthStr) : startMonth;
        endDate = DateTime(year, endMonth ?? startMonth ?? 1, endDay);
      } else {
        // fallback: try to parse first date in string
        final dateMatch = RegExp(r'(\w+)\s+(\d{1,2}),\s*(\d{4})').firstMatch(dateStr);
        if (dateMatch != null) {
          final month = _monthStringToInt(dateMatch.group(1)!);
          final day = int.tryParse(dateMatch.group(2)!);
          final year = int.tryParse(dateMatch.group(3)!);
          if (month != null && day != null && year != null) {
            startDate = DateTime(year, month, day);
            endDate = startDate;
          }
        }
      }
      int? daysAway;
      if (startDate != null) {
        daysAway = startDate.difference(now).inDays;
      }
      // Only add if the tournament has not ended yet (inclusive of today)
      if (endDate != null && (endDate.isAfter(now) || _isSameDay(endDate, now))) {
        final tWithDays = Map<String, dynamic>.from(t);
        tWithDays['daysAway'] = daysAway;
        upcomingWithDays.add(tWithDays);
      }
    }
    // Sort by daysAway ascending
    upcomingWithDays.sort((a, b) => (a['daysAway'] as int).compareTo(b['daysAway'] as int));
    if (upcomingWithDays.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            "no upcoming tournaments",
            style: TextStyle(
              color: Colors.white54,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: upcomingWithDays.length,
      itemBuilder: (context, index) {
        final t = upcomingWithDays[index];
        final origIndex = tournaments.indexWhere((orig) => orig['name'] == t['name']);
        final daysAway = t['daysAway'] as int;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Container(
            decoration: BoxDecoration(
              color: Color(0xFF232325),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              title: Row(
                children: [
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: t['name'] as String,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: '  (' + (daysAway == 0 ? 'Today' : daysAway == 1 ? '1 day away' : '$daysAway days away') + ')',
                            style: TextStyle(
                              color: Color(0xFF20B3D6),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5.0),
                child: Text(
                  '${t['date']} • ${t['country']} • ${t['players']} players • ELO ${t['elo']}',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              trailing: null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TournamentDetailsScreen(
                      tournament: t,
                      player: _searchQuery,
                      resultFilter: filterResultValue,
                      colorFilter: filterColorValue,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  int? _monthStringToInt(String month) {
    switch (month.toLowerCase()) {
      case 'jan':
      case 'january':
        return 1;
      case 'feb':
      case 'february':
        return 2;
      case 'mar':
      case 'march':
        return 3;
      case 'apr':
      case 'april':
        return 4;
      case 'may':
        return 5;
      case 'jun':
      case 'june':
        return 6;
      case 'jul':
      case 'july':
        return 7;
      case 'aug':
      case 'august':
        return 8;
      case 'sep':
      case 'september':
        return 9;
      case 'oct':
      case 'october':
        return 10;
      case 'nov':
      case 'november':
        return 11;
      case 'dec':
      case 'december':
        return 12;
      default:
        return null;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filteredTournaments;

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: Color(0xFF20B3D6),
        unselectedItemColor: Colors.white60,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events),
            label: 'Tournaments',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_books),
            label: 'Library',
          ),
        ],
        currentIndex: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              // Avatar
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFF20B3D6),
                    child: Text(
                      'TW',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Title
              Text(
                "Tournaments",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 18),
              // Search bar and filter icon
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(0xFF232325),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(Icons.search, color: Colors.white60, size: 22),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Search tournaments or players',
                                hintStyle: TextStyle(color: Colors.white54, fontSize: 15),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Pass filter state and setter to FilterButton
                  FilterButton(
                    resultValue: filterResultValue,
                    colorValue: filterColorValue,
                    onFilterChanged: (result, color) {
                      setState(() {
                        filterResultValue = result;
                        filterColorValue = color;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Tabs
              Row(
                children: [
                  Expanded(
                    child: MouseRegion(
                      onEnter: (_) {
                        setState(() {
                          _isAllEventsHovered = true;
                        });
                      },
                      onExit: (_) {
                        setState(() {
                          _isAllEventsHovered = false;
                        });
                      },
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTab = 0;
                          });
                        },
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 120),
                          height: 36,
                          decoration: BoxDecoration(
                            color: _selectedTab == 0
                                ? Color(0xFF18181A)
                                : _isAllEventsHovered
                                    ? Color(0xFF232325)
                                    : Color(0xFF171718),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(12),
                              bottomLeft: Radius.circular(12),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'All Events',
                              style: TextStyle(
                                color: _selectedTab == 0
                                    ? Colors.white
                                    : _isAllEventsHovered
                                        ? Color(0xFF20B3D6)
                                        : Colors.white38,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: MouseRegion(
                      onEnter: (_) {
                        setState(() {
                          _isUpcomingHovered = true;
                        });
                      },
                      onExit: (_) {
                        setState(() {
                          _isUpcomingHovered = false;
                        });
                      },
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTab = 1;
                          });
                        },
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 120),
                          height: 36,
                          decoration: BoxDecoration(
                            color: _selectedTab == 1
                                ? Color(0xFF18181A)
                                : _isUpcomingHovered
                                    ? Color(0xFF232325)
                                    : Color(0xFF171718),
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Upcoming Events',
                              style: TextStyle(
                                color: _selectedTab == 1
                                    ? Colors.white
                                    : _isUpcomingHovered
                                        ? Color(0xFF20B3D6)
                                        : Colors.white38,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Tournament list
              if (_selectedTab == 1)
                _buildUpcomingEventsList()
              else if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      "no tournaments found",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final t = filtered[index];
                    // Find the original index for favoriting
                    final origIndex = tournaments.indexOf(t);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Color(0xFF232325),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          title: Row(
                            children: [
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: t['name'] as String,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (t['status'] == 'LIVE')
                                        TextSpan(
                                          text: '  LIVE',
                                          style: TextStyle(
                                            color: Color(0xFF20B3D6),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        )
                                      else
                                        TextSpan(
                                          text: '  Completed',
                                          style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              // Show star icon only for LIVE tournaments
                              if (t['status'] == 'LIVE')
                                IconButton(
                                  icon: favoritedTournaments.contains(origIndex)
                                      ? Icon(Icons.star, color: Colors.amber, size: 22)
                                      : Icon(Icons.star_border, color: Colors.white70, size: 22),
                                  onPressed: () {
                                    setState(() {
                                      if (favoritedTournaments.contains(origIndex)) {
                                        favoritedTournaments.remove(origIndex);
                                      } else {
                                        favoritedTournaments.add(origIndex);
                                      }
                                    });
                                  },
                                  tooltip: favoritedTournaments.contains(origIndex)
                                      ? 'Unfavorite'
                                      : 'Favorite',
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5.0),
                            child: Text(
                              '${t['date']} • ${t['country']} • ${t['players']} players • ELO ${t['elo']}',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          trailing: index > 2
                              ? Icon(Icons.more_vert, color: Colors.white54, size: 22)
                              : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TournamentDetailsScreen(
                                  tournament: t,
                                  player: _searchQuery,
                                  resultFilter: filterResultValue,
                                  colorFilter: filterColorValue,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// Update FilterButton to accept and return filter state
class FilterButton extends StatelessWidget {
  final String resultValue;
  final String colorValue;
  final void Function(String result, String color) onFilterChanged;

  const FilterButton({
    Key? key,
    required this.resultValue,
    required this.colorValue,
    required this.onFilterChanged,
  }) : super(key: key);

  void _showFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 32, vertical: 60),
        child: Center(
          child: Container(
            width: 320,
            padding: EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Color(0xFF18181A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: FilterPopupContent(
              initialResultValue: resultValue,
              initialColorValue: colorValue,
              onApply: (selectedResult, selectedColor) {
                onFilterChanged(selectedResult, selectedColor);
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Color(0xFF232325),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showFilterDialog(context),
          child: Icon(Icons.filter_alt, color: Colors.white60, size: 22),
        ),
      ),
    );
  }
}

// Update FilterPopupContent to accept initial values and return on apply
class FilterPopupContent extends StatefulWidget {
  final String initialResultValue;
  final String initialColorValue;
  final void Function(String result, String color) onApply;

  const FilterPopupContent({
    Key? key,
    required this.initialResultValue,
    required this.initialColorValue,
    required this.onApply,
  }) : super(key: key);

  @override
  State<FilterPopupContent> createState() => _FilterPopupContentState();
}

class _FilterPopupContentState extends State<FilterPopupContent> {
  late String resultValue;
  late String colorValue;

  // Only show these in the dropdown, not "All Results"/"All Colors"
  final List<String> resultOptions = ['Wins', 'Losses', 'Draws'];
  final List<String> colorOptions = ['Black', 'White'];

  bool showResultDropdown = false;
  bool showColorDropdown = false;

  @override
  void initState() {
    super.initState();
    resultValue = widget.initialResultValue;
    colorValue = widget.initialColorValue;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Result Dropdown
        Text('Result', style: TextStyle(color: Colors.white70, fontSize: 14)),
        SizedBox(height: 6),
        GestureDetector(
          onTap: () => setState(() => showResultDropdown = !showResultDropdown),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Color(0xFF232325),
              borderRadius: BorderRadius.circular(6),
            ),
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  (resultValue == 'All Results' || resultValue.isEmpty)
                      ? 'All Results'
                      : resultValue,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: (resultValue == 'All Results' || resultValue.isEmpty)
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
                Icon(
                  showResultDropdown ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
        ),
        if (showResultDropdown)
          Container(
            margin: EdgeInsets.only(top: 2, bottom: 8),
            decoration: BoxDecoration(
              color: Color(0xFF232325),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: resultOptions.map((option) {
                return Material(
                  color: option == resultValue ? Color(0xFF18C7FF) : Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        resultValue = option;
                        showResultDropdown = false;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      child: Text(
                        option,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: option == resultValue ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        SizedBox(height: 12),
        // Color Dropdown
        Text('Color', style: TextStyle(color: Colors.white70, fontSize: 14)),
        SizedBox(height: 6),
        GestureDetector(
          onTap: () => setState(() => showColorDropdown = !showColorDropdown),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Color(0xFF232325),
              borderRadius: BorderRadius.circular(6),
            ),
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  (colorValue == 'All Colors' || colorValue.isEmpty)
                      ? 'All Colors'
                      : colorValue,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: (colorValue == 'All Colors' || colorValue.isEmpty)
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
                Icon(
                  showColorDropdown ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
        ),
        if (showColorDropdown)
          Container(
            margin: EdgeInsets.only(top: 2, bottom: 8),
            decoration: BoxDecoration(
              color: Color(0xFF232325),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: colorOptions.map((option) {
                return Material(
                  color: option == colorValue ? Color(0xFF18C7FF) : Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        colorValue = option;
                        showColorDropdown = false;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      child: Text(
                        option,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: option == colorValue ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    resultValue = 'All Results';
                    colorValue = 'All Colors';
                  });
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white24),
                  foregroundColor: Colors.white,
                  backgroundColor: Color(0xFF232325),
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text('Reset', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  widget.onApply(resultValue, colorValue);
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF18C7FF),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}