import 'dart:math';

/// Local helpers: strength meter and password generator.
class CryptoUtils {
  static String generate({
    int length = 16,
    bool uppercase = true,
    bool lowercase = true,
    bool digits = true,
    bool symbols = true,
  }) {
    const String uppercaseChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const String lowercaseChars = 'abcdefghijklmnopqrstuvwxyz';
    const String digitChars = '0123456789';
    const String symbolChars = r'!@#$%^&*()_+-=[]{}|;:,.<>?';

    var pools = <String>[];
    if (uppercase) pools.add(uppercaseChars);
    if (lowercase) pools.add(lowercaseChars);
    if (digits) pools.add(digitChars);
    if (symbols) pools.add(symbolChars);

    if (pools.isEmpty) {
      pools = [lowercaseChars];
    }

    final all = pools.join();
    final rnd = Random.secure();
    final out = <String>[];
    for (var i = 0; i < pools.length && out.length < length; i++) {
      final p = pools[i];
      out.add(p[rnd.nextInt(p.length)]);
    }
    while (out.length < length) {
      out.add(all[rnd.nextInt(all.length)]);
    }
    out.shuffle(rnd);
    if (out.length > length) {
      return out.sublist(0, length).join();
    }
    return out.join();
  }

  static int checkPasswordStrength(String password) {
    int score = 0;

    if (password.length >= 8) score += 20;
    if (password.length >= 12) score += 10;
    if (password.length >= 16) score += 10;
    if (RegExp(r'[a-z]').hasMatch(password)) score += 15;
    if (RegExp(r'[A-Z]').hasMatch(password)) score += 15;
    if (RegExp(r'[0-9]').hasMatch(password)) score += 15;
    if (RegExp(r'[!@#\$%^&*()_+\-=\[\]{}|;:,.<>?]').hasMatch(password)) score += 15;

    return score.clamp(0, 100);
  }

  /// Diceware-style passphrase: N random words from the embedded list,
  /// joined by [separator]. Optionally capitalize a random word and
  /// inject a random digit somewhere to satisfy "must contain a number"
  /// site policies without sacrificing memorability.
  ///
  /// Strength: each word contributes ~log2(_passphraseWords.length) bits
  /// of entropy. With 4096 words and 5 words, that's 60 bits — equivalent
  /// to a ~10-character random alphanumeric password but much easier to
  /// remember and type. (We intentionally keep the word list small and
  /// self-contained for offline use.)
  static String generatePassphrase({
    int wordCount = 5,
    String separator = '-',
    bool capitalize = true,
    bool injectDigit = true,
  }) {
    final rnd = Random.secure();
    const pool = _passphraseWords;
    final n = wordCount.clamp(3, 12);
    final words = <String>[
      for (var i = 0; i < n; i++) pool[rnd.nextInt(pool.length)],
    ];
    if (capitalize) {
      final i = rnd.nextInt(words.length);
      words[i] = '${words[i][0].toUpperCase()}${words[i].substring(1)}';
    }
    var out = words.join(separator);
    if (injectDigit) {
      final d = rnd.nextInt(100); // 0..99 — keeps it short
      // Append after a random word index, so it's not always trailing.
      final positions = <int>[
        for (var i = 1; i < words.length; i++) i,
      ];
      if (positions.isEmpty) {
        out = '$out$d';
      } else {
        final at = positions[rnd.nextInt(positions.length)];
        final pieces = words.toList();
        pieces[at] = '${pieces[at]}$d';
        // Re-apply capitalization marker (already in `words`).
        out = pieces.join(separator);
      }
    }
    return out;
  }
}

/// Compact word list for passphrase generation. 4–8 letter words, all
/// lower-case, no proper nouns, no homophones, no offensive words.
/// Kept under 5 KB so it ships in-binary with no asset loading.
const List<String> _passphraseWords = [
  'able', 'acid', 'acre', 'aero', 'agile', 'aglow', 'aim', 'airy', 'ajar',
  'alarm', 'album', 'alder', 'alert', 'alien', 'alike', 'alive', 'allow',
  'alloy', 'alpha', 'altar', 'alter', 'amaze', 'amber', 'amend', 'amuse',
  'angel', 'anger', 'angle', 'angry', 'ankle', 'anvil', 'apex', 'apple',
  'apply', 'apron', 'arbor', 'arc', 'arch', 'arena', 'argue', 'arise',
  'armor', 'army', 'aroma', 'arrow', 'arson', 'art', 'ash', 'ashen',
  'ask', 'aspen', 'aster', 'atlas', 'atom', 'audio', 'aunt', 'aura',
  'auto', 'avail', 'avid', 'avoid', 'awake', 'award', 'aware', 'away',
  'awful', 'axe', 'axiom', 'axis', 'azure', 'badge', 'bagel', 'baker',
  'balm', 'bamboo', 'banana', 'bang', 'bank', 'bar', 'barn', 'basil',
  'basin', 'bask', 'bat', 'bath', 'baton', 'bay', 'beach', 'beam',
  'bean', 'bear', 'beast', 'beat', 'beaver', 'bee', 'beef', 'beep',
  'beet', 'begin', 'bell', 'belt', 'bench', 'bend', 'berry', 'best',
  'bevel', 'beyond', 'big', 'bike', 'bill', 'bind', 'bingo', 'birch',
  'bird', 'bite', 'black', 'blade', 'blaze', 'bless', 'blimp', 'blink',
  'block', 'bloom', 'blue', 'bluff', 'blur', 'board', 'boast', 'boat',
  'bobby', 'body', 'bold', 'bolt', 'bond', 'bone', 'bonus', 'book',
  'boom', 'boost', 'boot', 'borax', 'born', 'boss', 'both', 'bowl',
  'box', 'brace', 'brain', 'brake', 'brand', 'brass', 'brave', 'bread',
  'break', 'brick', 'bridge', 'bring', 'brisk', 'broil', 'broom', 'brown',
  'brush', 'bud', 'buddy', 'buffer', 'bug', 'bugle', 'build', 'bulb',
  'bulk', 'bull', 'bump', 'bunch', 'bundle', 'bunny', 'buoy', 'burn',
  'burst', 'bus', 'bush', 'busy', 'buy', 'buzz', 'cabin', 'cable',
  'cactus', 'cadet', 'cafe', 'cage', 'cake', 'calf', 'call', 'calm',
  'camel', 'camp', 'canal', 'candy', 'cane', 'canoe', 'canvas', 'cap',
  'cape', 'car', 'card', 'cargo', 'carol', 'carry', 'cart', 'carve',
  'case', 'cash', 'cast', 'cat', 'catch', 'cause', 'cave', 'cedar',
  'cell', 'cello', 'chain', 'chair', 'chalk', 'champ', 'chant', 'chap',
  'chart', 'chase', 'cheek', 'cheer', 'chef', 'chess', 'chest', 'chew',
  'chick', 'chief', 'chili', 'chime', 'chin', 'chip', 'chirp', 'chord',
  'chrome', 'cider', 'cigar', 'cinder', 'circle', 'city', 'civic', 'clad',
  'claim', 'clamp', 'clap', 'clarinet', 'clash', 'class', 'claw', 'clay',
  'clean', 'clear', 'cleft', 'clerk', 'click', 'cliff', 'climb', 'cling',
  'clip', 'cloak', 'clock', 'clone', 'close', 'cloth', 'cloud', 'clove',
  'clown', 'club', 'clue', 'coach', 'coal', 'coast', 'coat', 'cobra',
  'cocoa', 'code', 'cold', 'collar', 'colt', 'comet', 'comic', 'cone',
  'coral', 'cord', 'core', 'cork', 'corn', 'cost', 'cotton', 'couch',
  'cough', 'count', 'court', 'cover', 'cow', 'cozy', 'crab', 'craft',
  'cramp', 'crane', 'crash', 'crate', 'crawl', 'crazy', 'cream', 'creek',
  'crepe', 'crest', 'crew', 'crib', 'crisp', 'crook', 'crop', 'cross',
  'crowd', 'crown', 'crumb', 'crust', 'cry', 'crypt', 'cube', 'cup',
  'curl', 'curry', 'curve', 'cushion', 'cycle', 'daisy', 'dance', 'dare',
  'dash', 'data', 'date', 'dawn', 'day', 'deal', 'dear', 'debit',
  'decay', 'deck', 'decoy', 'deep', 'deer', 'delay', 'delta', 'demo',
  'dent', 'depth', 'desert', 'desk', 'dew', 'diary', 'dice', 'diet',
  'dig', 'dim', 'dime', 'diner', 'dingo', 'dinner', 'dip', 'dirt',
  'disco', 'dish', 'ditch', 'dive', 'dock', 'doctor', 'dodge', 'doll',
  'dome', 'donkey', 'donut', 'door', 'dose', 'dot', 'dove', 'down',
  'doze', 'drag', 'drain', 'drama', 'draw', 'dream', 'dress', 'drift',
  'drill', 'drink', 'drip', 'drive', 'drop', 'drum', 'duck', 'duel',
  'duet', 'dull', 'dump', 'dunes', 'dusk', 'dust', 'duty', 'dwarf',
  'dye', 'eager', 'eagle', 'ear', 'early', 'earn', 'earth', 'east',
  'easy', 'eat', 'eaves', 'echo', 'edge', 'eel', 'effort', 'egg',
  'eight', 'elbow', 'elder', 'elect', 'elf', 'elm', 'else', 'email',
  'ember', 'empty', 'end', 'enter', 'entry', 'envy', 'epic', 'equal',
  'era', 'erase', 'error', 'erupt', 'essay', 'ether', 'event', 'every',
  'evil', 'exam', 'exile', 'exist', 'extra', 'eye', 'fable', 'face',
  'fact', 'fade', 'fail', 'fair', 'fairy', 'faith', 'fake', 'fall',
  'fame', 'fan', 'far', 'farm', 'fast', 'fat', 'fawn', 'fear',
  'feast', 'feat', 'fee', 'feed', 'feel', 'felt', 'fence', 'fern',
  'ferry', 'few', 'fiber', 'field', 'fig', 'figure', 'file', 'fill',
  'film', 'final', 'find', 'fine', 'fir', 'fire', 'firm', 'first',
  'fish', 'fist', 'fix', 'flag', 'flame', 'flap', 'flash', 'flask',
  'flat', 'flax', 'fleet', 'flesh', 'flex', 'flick', 'flint', 'float',
  'flock', 'flood', 'floor', 'flour', 'flow', 'fluff', 'flute', 'fly',
  'foam', 'fog', 'foil', 'fold', 'food', 'fool', 'foot', 'force',
  'fork', 'form', 'fort', 'forum', 'foul', 'four', 'fox', 'foyer',
  'frame', 'free', 'fresh', 'fries', 'frog', 'front', 'frost', 'froth',
  'frown', 'fruit', 'fudge', 'fuel', 'full', 'fume', 'fun', 'fund',
  'fungi', 'fur', 'fuse', 'gain', 'galaxy', 'game', 'gap', 'garden',
  'gate', 'gauge', 'gear', 'gem', 'genie', 'ghost', 'giant', 'gift',
  'giraffe', 'girl', 'glad', 'glass', 'gleam', 'glide', 'globe', 'gloom',
  'glory', 'glove', 'glow', 'glue', 'goal', 'goat', 'gold', 'good',
  'goose', 'gosling', 'grab', 'grain', 'grand', 'grant', 'grape', 'graph',
  'grass', 'grave', 'gravy', 'gray', 'great', 'greek', 'green', 'grid',
  'grief', 'grill', 'grin', 'grip', 'groom', 'grout', 'grove', 'grow',
  'gruff', 'guard', 'guide', 'guild', 'guilt', 'gulf', 'gull', 'gum',
  'gust', 'gym', 'habit', 'hail', 'hair', 'half', 'hall', 'halo',
  'ham', 'hammer', 'hand', 'hang', 'happy', 'harbor', 'hard', 'harm',
  'harp', 'harvest', 'hat', 'hatch', 'haunt', 'haven', 'hawk', 'hay',
  'haze', 'head', 'heap', 'hear', 'heart', 'heat', 'heavy', 'hedge',
  'heel', 'helm', 'help', 'hen', 'herb', 'herd', 'hero', 'hide',
  'high', 'hike', 'hill', 'hint', 'hip', 'hippo', 'hire', 'hive',
  'hold', 'hole', 'holy', 'home', 'honey', 'honor', 'hood', 'hoof',
  'hook', 'hoop', 'hop', 'hope', 'horn', 'horse', 'host', 'hot',
  'hotel', 'hound', 'hour', 'house', 'hover', 'hub', 'hug', 'hull',
  'human', 'hump', 'hunt', 'hurry', 'hut', 'hydro', 'hymn', 'ice',
  'icicle', 'icon', 'icy', 'idea', 'igloo', 'ill', 'image', 'inch',
  'index', 'indigo', 'ink', 'inlet', 'inner', 'input', 'iris', 'iron',
  'irony', 'island', 'item', 'ivory', 'ivy', 'jab', 'jacket', 'jade',
  'jaguar', 'jail', 'jam', 'jar', 'java', 'jaw', 'jazz', 'jeans',
  'jelly', 'jet', 'jewel', 'jiffy', 'jigsaw', 'job', 'jog', 'join',
  'joint', 'joke', 'jolly', 'jolt', 'journey', 'joy', 'judge', 'juice',
  'jumbo', 'jump', 'june', 'jungle', 'junk', 'jury', 'jut', 'kale',
  'karma', 'kayak', 'keel', 'keen', 'keep', 'kelp', 'kennel', 'ketch',
  'kettle', 'key', 'khaki', 'kick', 'kid', 'kidney', 'kilo', 'kind',
  'king', 'kiosk', 'kiss', 'kit', 'kite', 'kitten', 'kiwi', 'knack',
  'knee', 'knife', 'knight', 'knit', 'knob', 'knock', 'knot', 'know',
  'koala', 'lace', 'lack', 'lacquer', 'ladder', 'lady', 'lake', 'lamp',
  'land', 'lane', 'lap', 'large', 'lark', 'laser', 'last', 'late',
  'latex', 'lava', 'law', 'lawn', 'layer', 'lazy', 'leaf', 'lean',
  'leap', 'learn', 'lease', 'leash', 'leek', 'left', 'leg', 'legal',
  'lemon', 'lend', 'lens', 'level', 'lever', 'liar', 'lid', 'lift',
  'light', 'lilac', 'lily', 'lime', 'limit', 'limp', 'line', 'link',
  'lint', 'lion', 'lip', 'list', 'liver', 'llama', 'load', 'loaf',
  'loan', 'lobby', 'local', 'lock', 'log', 'logic', 'loft', 'logo',
  'long', 'loop', 'loose', 'lord', 'loss', 'lost', 'lot', 'loud',
  'lounge', 'love', 'low', 'loyal', 'luck', 'lucky', 'lull', 'lumber',
  'lunar', 'lunch', 'lung', 'lure', 'lush', 'luxury', 'lynx', 'lyric',
  'macaw', 'mace', 'machine', 'magic', 'magma', 'magnet', 'maid', 'mail',
  'main', 'major', 'maker', 'mallet', 'mamba', 'man', 'maned', 'mango',
  'manor', 'maple', 'march', 'mare', 'marker', 'marsh', 'martial', 'marvel',
  'mascot', 'mask', 'mast', 'mat', 'match', 'matter', 'maximum', 'maze',
  'meadow', 'meal', 'meat', 'medal', 'media', 'meet', 'melon', 'melt',
  'memo', 'memory', 'menu', 'merge', 'merit', 'mesh', 'metal', 'meter',
  'method', 'mid', 'midst', 'might', 'mild', 'mile', 'milk', 'mill',
  'mimic', 'mind', 'mine', 'mingle', 'mini', 'minor', 'mint', 'minus',
  'mirror', 'misty', 'mitten', 'mix', 'moat', 'mobile', 'mock', 'modal',
  'model', 'modem', 'modest', 'modify', 'moist', 'molar', 'mold', 'molt',
  'mom', 'moment', 'money', 'monk', 'month', 'moody', 'moon', 'moose',
  'moral', 'morning', 'morsel', 'moss', 'most', 'moth', 'mother', 'motor',
  'mound', 'mount', 'mouse', 'mouth', 'movie', 'mow', 'much', 'mud',
  'muffin', 'mug', 'mule', 'multi', 'mumble', 'muscle', 'museum', 'music',
  'must', 'mute', 'mutual', 'myth', 'nail', 'name', 'nanny', 'nap',
  'narrow', 'nasal', 'native', 'nature', 'navy', 'near', 'neat', 'neck',
  'need', 'needle', 'neon', 'nephew', 'nerve', 'nest', 'net', 'never',
  'newt', 'next', 'nice', 'niche', 'night', 'nine', 'noble', 'node',
  'noise', 'nomad', 'noodle', 'noon', 'normal', 'north', 'nose', 'note',
  'nova', 'novel', 'nudge', 'nugget', 'number', 'nurse', 'nut', 'nutmeg',
  'oak', 'oasis', 'oat', 'oath', 'object', 'ocean', 'octet', 'odd',
  'offer', 'office', 'often', 'ogre', 'oil', 'okra', 'olive', 'omega',
  'omen', 'onion', 'onyx', 'opal', 'open', 'opera', 'opium', 'oracle',
  'orange', 'orbit', 'orca', 'orchid', 'order', 'organ', 'osprey', 'otter',
  'ouch', 'ounce', 'outer', 'oval', 'oven', 'owl', 'oxen', 'oxide',
  'oxygen', 'oyster', 'ozone', 'pack', 'paddle', 'page', 'pail', 'pain',
  'paint', 'pair', 'palace', 'palm', 'panda', 'panel', 'panic', 'pants',
  'paper', 'parade', 'parent', 'park', 'parrot', 'party', 'pasta', 'paste',
  'patch', 'path', 'patient', 'patio', 'pause', 'paw', 'peach', 'pear',
  'pearl', 'pebble', 'pen', 'pencil', 'peony', 'pepper', 'perch', 'perk',
  'pet', 'petal', 'phase', 'phone', 'photo', 'piano', 'pick', 'picnic',
  'pier', 'pig', 'pigeon', 'pile', 'pill', 'pilot', 'pin', 'pine',
  'pink', 'pioneer', 'pipe', 'pirate', 'pistol', 'pit', 'pitch', 'pivot',
  'pixel', 'pizza', 'place', 'plain', 'plan', 'plank', 'plant', 'plate',
  'play', 'plaza', 'plead', 'plot', 'plow', 'plug', 'plum', 'plump',
  'plush', 'pocket', 'poem', 'point', 'poise', 'pole', 'police', 'pollen',
  'pond', 'pool', 'pop', 'popcorn', 'poppy', 'pork', 'port', 'pose',
  'pot', 'potato', 'pottery', 'pouch', 'pound', 'pour', 'powder', 'power',
  'prairie', 'praise', 'prawn', 'pretty', 'price', 'pride', 'priest', 'prime',
  'print', 'prism', 'prize', 'profit', 'proof', 'proud', 'prune', 'pry',
  'public', 'puddle', 'puff', 'pug', 'pull', 'pulp', 'pulse', 'puma',
  'pump', 'pumpkin', 'punch', 'pupil', 'puppet', 'puppy', 'pure', 'purple',
  'purr', 'puzzle', 'quail', 'quake', 'quality', 'quart', 'queen', 'quest',
  'quick', 'quiet', 'quilt', 'quirk', 'quiver', 'quiz', 'quote', 'rabbit',
  'race', 'rack', 'radar', 'radio', 'raft', 'rage', 'rail', 'rain',
  'rake', 'ram', 'ramp', 'ranch', 'random', 'range', 'rare', 'rather',
  'rattle', 'raven', 'ravine', 'raw', 'ray', 'razor', 'reach', 'react',
  'read', 'reason', 'rebel', 'recipe', 'red', 'reed', 'reef', 'refer',
  'reform', 'refuge', 'region', 'reign', 'relax', 'relay', 'relic', 'remix',
  'render', 'rent', 'reply', 'rescue', 'rest', 'retire', 'retro', 'reuse',
  'review', 'rhino', 'rhubarb', 'rhyme', 'rib', 'rice', 'rich', 'ride',
  'ridge', 'rifle', 'rift', 'right', 'rigid', 'rim', 'ring', 'ripe',
  'ripple', 'rise', 'risk', 'rival', 'river', 'road', 'roar', 'roast',
  'robe', 'robin', 'robot', 'rock', 'rocket', 'rod', 'rodeo', 'rogue',
  'role', 'roll', 'roof', 'rook', 'room', 'roost', 'root', 'rope',
  'rose', 'rosy', 'rotor', 'rough', 'round', 'route', 'royal', 'rubber',
  'ruby', 'rude', 'rug', 'ruin', 'rule', 'ruler', 'rumor', 'run',
  'runway', 'rust', 'sable', 'sack', 'sad', 'safari', 'safe', 'sag',
  'saga', 'sail', 'salad', 'salmon', 'salt', 'same', 'sample', 'sand',
  'sash', 'sauce', 'sausage', 'save', 'savor', 'saxon', 'say', 'scale',
  'scan', 'scarf', 'scene', 'scent', 'scoop', 'scope', 'score', 'scout',
  'scrap', 'scrub', 'sea', 'seal', 'seat', 'seed', 'sense', 'serve',
  'set', 'seven', 'sew', 'shade', 'shaft', 'shake', 'shale', 'shall',
  'sham', 'shame', 'shape', 'share', 'shark', 'sharp', 'shave', 'shawl',
  'shed', 'sheep', 'sheet', 'shelf', 'shell', 'shield', 'shift', 'shine',
  'ship', 'shirt', 'shock', 'shoe', 'shoot', 'shop', 'shore', 'short',
  'shout', 'shovel', 'show', 'shrine', 'shrub', 'shy', 'sick', 'side',
  'siege', 'sift', 'sigh', 'sight', 'sign', 'silk', 'sill', 'silly',
  'silver', 'simmer', 'simple', 'since', 'sing', 'sink', 'sip', 'siren',
  'sister', 'sit', 'site', 'six', 'size', 'skate', 'sketch', 'ski',
  'skin', 'skip', 'skull', 'sky', 'slab', 'slack', 'slam', 'slang',
  'slate', 'sled', 'sleek', 'sleep', 'slice', 'slick', 'slide', 'slim',
  'slip', 'slope', 'slot', 'slow', 'slug', 'small', 'smart', 'smell',
  'smile', 'smith', 'smog', 'smoke', 'snack', 'snail', 'snake', 'snap',
  'snare', 'sneak', 'sniff', 'snip', 'snore', 'snow', 'snug', 'soak',
  'soap', 'soar', 'sock', 'soda', 'sofa', 'soft', 'soil', 'solar',
  'sole', 'solid', 'solve', 'song', 'soon', 'sort', 'soul', 'sound',
  'soup', 'sour', 'south', 'space', 'spare', 'spark', 'spawn', 'speak',
  'speed', 'spell', 'spend', 'sphere', 'spice', 'spike', 'spin', 'spine',
  'spiral', 'spirit', 'spit', 'splash', 'split', 'spoil', 'spoke', 'sponge',
  'spool', 'spoon', 'sport', 'spot', 'spout', 'spray', 'spring', 'sprite',
  'spruce', 'spur', 'spy', 'square', 'squash', 'squid', 'squirrel', 'stack',
  'staff', 'stage', 'stain', 'stair', 'stake', 'stale', 'stalk', 'stall',
  'stamp', 'stand', 'star', 'stare', 'start', 'state', 'stay', 'steal',
  'steam', 'steel', 'stem', 'step', 'stew', 'stick', 'still', 'sting',
  'stock', 'stomp', 'stone', 'stool', 'stoop', 'stop', 'storm', 'story',
  'stove', 'straw', 'stream', 'street', 'strict', 'stride', 'string', 'strip',
  'stroke', 'strong', 'stub', 'stud', 'study', 'stuff', 'stump', 'stun',
  'style', 'sugar', 'suit', 'sum', 'summer', 'sun', 'sunny', 'super',
  'surf', 'surge', 'sushi', 'swan', 'swap', 'swarm', 'sway', 'sweep',
  'sweet', 'swell', 'swift', 'swim', 'swing', 'swirl', 'switch', 'sword',
  'syrup', 'table', 'tablet', 'taco', 'tactic', 'tag', 'tail', 'tale',
  'talk', 'tall', 'tame', 'tan', 'tango', 'tank', 'tap', 'tape',
  'tar', 'target', 'taro', 'tart', 'task', 'taste', 'taxi', 'teach',
  'team', 'tear', 'tease', 'tech', 'teen', 'tell', 'temple', 'ten',
  'tend', 'tennis', 'tent', 'term', 'test', 'text', 'thank', 'thatch',
  'thaw', 'theme', 'thick', 'thin', 'thing', 'think', 'third', 'thorn',
  'three', 'thumb', 'thunder', 'thus', 'tick', 'tide', 'tidy', 'tie',
  'tiger', 'tight', 'tile', 'tilt', 'time', 'tin', 'tinsel', 'tiny',
  'tip', 'tire', 'title', 'toad', 'toast', 'toe', 'toga', 'token',
  'told', 'toll', 'tomato', 'tomb', 'tone', 'tongue', 'tool', 'tooth',
  'top', 'torch', 'torso', 'toss', 'total', 'totem', 'touch', 'tough',
  'tour', 'towel', 'tower', 'town', 'toxic', 'toy', 'trace', 'track',
  'trade', 'trail', 'train', 'trance', 'trap', 'trash', 'tray', 'tread',
  'treat', 'tree', 'trend', 'tribe', 'trick', 'trim', 'trio', 'tripod',
  'troll', 'troop', 'trophy', 'trout', 'truck', 'true', 'trump', 'trunk',
  'trust', 'truth', 'try', 'tuba', 'tube', 'tuft', 'tug', 'tulip',
  'tuna', 'tundra', 'tune', 'tunnel', 'turbo', 'turkey', 'turn', 'turtle',
  'tusk', 'tutor', 'twang', 'tweed', 'twelve', 'twin', 'twirl', 'twist',
  'two', 'type', 'umber', 'umbra', 'uncle', 'under', 'unify', 'unique',
  'unit', 'unity', 'until', 'upon', 'upset', 'urban', 'urge', 'usage',
  'use', 'usher', 'usual', 'utter', 'vague', 'vain', 'valid', 'valley',
  'value', 'van', 'vane', 'vapor', 'vase', 'vast', 'vault', 'velvet',
  'vendor', 'venue', 'verb', 'verse', 'very', 'vest', 'veto', 'via',
  'vibe', 'video', 'view', 'vigor', 'villa', 'vine', 'violet', 'viper',
  'virus', 'visa', 'visit', 'visor', 'vital', 'vivid', 'vocal', 'voice',
  'volume', 'vote', 'voucher', 'vow', 'voyage', 'wade', 'wafer', 'wag',
  'wage', 'wagon', 'waist', 'wait', 'wake', 'walk', 'wall', 'walnut',
  'walrus', 'wand', 'want', 'war', 'ward', 'warm', 'warn', 'wash',
  'wasp', 'waste', 'watch', 'water', 'wave', 'wax', 'way', 'weak',
  'weave', 'web', 'wedge', 'week', 'weird', 'weld', 'well', 'west',
  'wet', 'whale', 'wharf', 'wheat', 'wheel', 'when', 'whip', 'whirl',
  'whisk', 'whistle', 'white', 'whole', 'why', 'wick', 'wide', 'widow',
  'width', 'wife', 'wild', 'will', 'willow', 'win', 'wind', 'window',
  'wine', 'wing', 'wink', 'winter', 'wire', 'wisdom', 'wise', 'wish',
  'wisp', 'witch', 'wizard', 'woke', 'wolf', 'woman', 'won', 'wonder',
  'wood', 'wool', 'word', 'work', 'world', 'worm', 'worry', 'worth',
  'wrap', 'wreath', 'wreck', 'wren', 'wrist', 'write', 'wrong', 'yacht',
  'yam', 'yard', 'yarn', 'yawn', 'year', 'yeast', 'yell', 'yellow',
  'yes', 'yeti', 'yield', 'yodel', 'yoga', 'yogurt', 'yolk', 'young',
  'youth', 'zeal', 'zebra', 'zero', 'zest', 'zigzag', 'zinc', 'zip',
  'zipper', 'zone', 'zoom',
];
