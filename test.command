#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/checks
swiftc Sources/Chappie/Voice.swift Sources/Chappie/PurchaseRules.swift Sources/Chappie/Intent.swift Sources/Chappie/GarbageCalendar.swift Sources/Chappie/Booking.swift Sources/Chappie/AmazonSession.swift Tests/ChappieTests/ChappieTests.swift -o .build/checks/RulesTests
.build/checks/RulesTests
