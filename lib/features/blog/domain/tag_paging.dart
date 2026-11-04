/// How many articles one tag page holds.
///
/// The API caps `limit` at 100 and defaults this route to 20; a page that
/// comes back shorter than this is the end of the list, which is the only
/// "has more" signal the endpoint offers.
const int kTagPageSize = 20;
