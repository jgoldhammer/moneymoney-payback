-- ---------------------------------------------------------------------------------------------------------------------
--
-- MoneyMoney Web Banking Extension
-- http://moneymoney-app.com/api/webbanking
--
--
-- The MIT License (MIT)
--
-- Copyright (c) 2012-2014 MRH applications GmbH
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- ---------------------------------------------------------------------------------------------------------------------

-- ---------------------------------------------------------------------------------------------------------------------
--
-- Get portfolio of DWS Investments.
--
-- ATTENTION: This extension requires MoneyMoney version 2.2.2 or higher
--
-- ---------------------------------------------------------------------------------------------------------------------


-- ---------------------------------------------------------------------------------------------------------------------
-- Common MoneyMoney extension informations
-- ---------------------------------------------------------------------------------------------------------------------

WebBanking {
    version = 1.00,
    country = "de",
    url = "https://www.payback.de/pb/authenticate/id/713416/#loginSecureTab",
    services    = {"Payback Points Accounts},
    description = string.format(MM.localizeText("Get points of %s"), "Payback account")
}

-- ---------------------------------------------------------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------------------------------------------------------

local function strToAmount(str)
    -- Helper function for converting localized amount strings to Lua numbers.
    print('raw value: '+str)
    local convertedValue = string.gsub(string.gsub(string.gsub(str, " .+", ""), "%.", ""), ",", ".")
    print('converted value '+convertedValue)
    return convertedValue
end

-- ---------------------------------------------------------------------------------------------------------------------

local function strToAmountWithDefault(str, defaultValue)
    -- Helper function for converting localized amount strings to Lua numbers with a default value.
    local value = strToAmount(str)
    if value == nil or value == "" then
        value = defaultValue
    end
    return value
end

-- ---------------------------------------------------------------------------------------------------------------------

local function strToDate(str)
    -- Helper function for converting localized date strings to timestamps.
    local d, m, y = string.match(str, "(%d%d)%.(%d%d)%.(%d%d%d%d)")
    if d and m and y then
        return os.time { year = y, month = m, day = d, hour = 0, min = 0, sec = 0 }
    end
end

-- ---------------------------------------------------------------------------------------------------------------------

local function printElementWithPrefix(prefix, element)
    -- Helper function  for debugging HTML elements with a prtinable prefix
    if element:children():length() >= 1 then
        element:children():each(function(index, element2)
            local newPrefix = prefix .. "-" .. index
            print(newPrefix .. "=" .. element2:text())
            printElementWithPrefix(newPrefix, element2)
        end)
    end
end

-- ---------------------------------------------------------------------------------------------------------------------


local function strToFullDate (str)
    -- Helper function for converting localized date strings to timestamps.
    local d, m, y = string.match(str, "(%d%d).(%d%d).(%d%d%d%d)")
    return os.time{year=y, month=m, day=d}
end

local function printElement(element)
    -- Helper function  for debugging HTML elements
    printElementWithPrefix('0', element)
end


-- ---------------------------------------------------------------------------------------------------------------------
-- The following variables are used to save state.
-- ---------------------------------------------------------------------------------------------------------------------

local connection
local overview_html


-- ---------------------------------------------------------------------------------------------------------------------
--
-- MoneyMoney API Extension
--
-- @see: http://moneymoney-app.com/api/webbanking/
--
-- ---------------------------------------------------------------------------------------------------------------------

function SupportsBank(protocol, bankCode)
    -- Using artificial bankcode to identify the DWS Investments group.
    return protocol == ProtocolWebBanking and bankCode == "Payback"
end

-- ---------------------------------------------------------------------------------------------------------------------

function InitializeSession(protocol, bankCode, username, customer, password)

    print("InitializeSession with " .. protocol .. " connecting " .. url)
    MM.printStatus("Start to login...")

    -- Create HTTPS connection object.
    connection = Connection()
    connection.language = "de-de"

    -- Fetch login page.
    local html = HTML(connection:get(url))

    -- Fill in login credentials.
    html:xpath("//*[@id='aliasInputSecure']"):attr("value", username)
    html:xpath("//*[@id='passwordInput']"):attr("value", password)

    -- Submit login form.
    overview_html = HTML(connection:request(html:xpath("//*[@id='loginSubmitButtonSecure']"):submit()))

    -- Check for failed login.
    local failure = overview_html:xpath("//*[@id='errorNotification']")
    if failure:length() > 0 then
        print("Login failed. Reason: " .. failure:xpath("//*p[@class='MsoNormal']"))
        MM.printStatus("Login failed...");
        return LoginFailed
    end

    overview_html = HTML(connection:request(overview_html:xpath("//ul[@class='secondary-nav tracking-event-module']/li[3]/a"):click()))

    print("Session initialization completed successfully.")
    MM.printStatus("Login successfull...")
    return nil
end

-- ---------------------------------------------------------------------------------------------------------------------

function ListAccounts(knownAccounts)

    -- Supports only one account
    local account = {
        owner = overview_html:xpath("//*/p[@class='welcome-msg']/strong"):text(),
        name = "Paypack Punkte Konto",
        accountNumber = overview_html:xpath("//p[text()='Kundennummer:']/span"):text(),
        portfolio = false,
        currency = "EUR",
        type = AccountTypeUnknown
    }

    return { account }
end

-- ---------------------------------------------------------------------------------------------------------------------

function RefreshAccount(account, since)
    local transactions = {}

    -- the datefields can be filled directly
    html:xpath("//input[@id='date1']"):attr("value", os.date("%d.%m.%Y", since))
    html:xpath("//input[@id='date2']"):attr("value", os.date("%d.%m.%Y"))

    print("Submitting transaction search form for " .. account.accountNumber)
    html = HTML(connection:request(html:xpath("//form[@id='pointRangeForm']"):submit()))

    -- Get paypack points from text next to select box
    local balance = html:xpath("//*span[@id='serverPoints']"):text()

    -- Check if the HTML table with transactions exists.
    if html:xpath("//table[@class='mypoints']/tbody/tr[1]/td[1]"):length() > 0 then

        -- Extract transactions.

        html:xpath("//table[@class='mypoints']/tbody/tr[position()>1]"):each(function (index, row)
            local columns = row:children()

            local transaction = {
                valueDate   = strToFullDate(columns:get(1):text()),
                bookingDate = strToFullDate(columns:get(1):text()),
                name        = columns:get(2):text(),
                purpose     = columns:get(3):text(),
                currency    = "EUR",
                amount      = strToAmount(columns:get(4):text(), true)
            }

            table.insert(transactions, transaction)
        end)

    end

    -- Return balance and array of transactions.
    return {balance=balance, transactions=transactions, securities=nil}
end

-- ---------------------------------------------------------------------------------------------------------------------

function EndSession()

    -- Submit logout form.
    local logout_html = HTML(connection:request(overview_html:xpath("//*[@id='pbLogin]"):click()))

    print("Logged out successfully!")
end
