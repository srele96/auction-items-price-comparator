# AuctionItemsPriceComparator

Writes the auction items name and price to a file _(saved variables)_.

## Todo

### Wipe database before scan

- it may show inacurate results existing cheapest item in db doesnt have to mean its cheapest in database
- if existing item isn't listed on auction house, it's also incorrect data - outdated

### Adjust price comparing algorithm

- Currently checking if item's gold is more expensive than other item gold
- what if item A has 5g and item B has 0g 50s? this is also huge n times profit

### Saved string is difficult to copy paste, find a way to extract it

### Diferentiation algorithm - save total amount of listings on auction house for each item

- If both items on icc and fm have low amount of listings, it's probably not used at all
- But have another list that does not excluse such items

### Make extracting json string from .lua file database easier
