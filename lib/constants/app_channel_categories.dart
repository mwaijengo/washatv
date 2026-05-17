/// Channel categories used in Home, Categories, and Admin — single source of truth.
/// DB / API values stay in English; UI uses [categoryDisplayName].
const List<String> kAppChannelCategories = <String>[
  'Sports',
  'Movies',
  'News',
  'Trending',
  'Kids',
  'Wildlife',
];

const String kSectionFreeChannelsTitle = 'Chaneli za bure';
const String kSectionPremiumChannelsTitle = 'Chaneli za Premium';

const Map<String, String> kCategoryDisplayNames = <String, String>{
  'All': 'Zote',
  'Sports': 'Michezo',
  'Movies': 'Tamthilia',
  'News': 'Habari',
  'Trending': 'Pendwa',
  'Kids': 'Katuni',
  'Wildlife': 'Wanyama',
};

String categoryDisplayName(String categoryKey) =>
    kCategoryDisplayNames[categoryKey] ?? categoryKey;

/// Badge on channel cards: Bure / Imefungwa / Imefunguliwa.
String channelAccessLabel({required bool channelPremium, required bool locked}) {
  if (!channelPremium) return 'Bure';
  if (locked) return 'Imefungwa';
  return 'Imefunguliwa';
}
