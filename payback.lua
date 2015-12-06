-- ---------------------------------------------------------------------------------------------------------------------
--
-- MoneyMoney Web Banking Extension
-- http://moneymoney-app.com/api/webbanking
--
--
-- The MIT License (MIT)
--
-- Copyright (c) 2012-2015 MRH applications GmbH
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
-- Get portfolio of Payback online account.
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
    services    = {"Payback-Punkte"},
    description = string.format(MM.localizeText("Get points of %s"), "Payback account")
}

-- ---------------------------------------------------------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------------------------------------------------------

local function strToAmount(str)
    -- Helper function for converting localized amount strings to Lua numbers.
    print("raw value: ".. str)
    local convertedValue = string.gsub(string.gsub(string.gsub(str, " .+", ""), "%.", ""), ",", ".")
    print("converted value " .. convertedValue)
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
  return bankCode == "Payback-Punkte" and protocol == ProtocolWebBanking
end

-- ---------------------------------------------------------------------------------------------------------------------

function InitializeSession(protocol, bankCode, username, customer, password)

    print("InitializeSession with " .. protocol .. " connecting " .. url .. "with ".. username)
    MM.printStatus("Start to login...")

    -- Create HTTPS connection object.
    connection = Connection()
    connection.language = "de-de"

    -- Fetch login page.
    local loginPage = HTML(connection:get(url))

    -- Fill in login credentials.
    loginPage:xpath("//*[@id='aliasInputSecure']"):attr("value", username)
    loginPage:xpath("//*[@id='passwordInput']"):attr("value", password)

    MM.printStatus("parameters filled in ");

    -- Submit login form.
    local request = connection:request(loginPage:xpath("//input[@id='loginSubmitButtonSecure']"):click())

    MM.printStatus("request " ..request)
    overview_html = HTML(request)

    -- Check for failed login.
    local failure = overview_html:xpath("//*[@id='errorNotification']")
    if failure:length() > 0 then
        print("Login failed. Reason: " .. failure:xpath("//*p[@class='MsoNormal']"))
        MM.printStatus("Login failed...");
        return LoginFailed
    end

    MM.printStatus("Login success- go to correct paypack page ");


    overview_html = HTML(connection:request(overview_html:xpath("//ul[@class='secondary-nav tracking-event-module']/li[3]/a"):click()))

    print("Session initialization completed successfully.")
    MM.printStatus("Login successfull...")
    return nil
end

-- ---------------------------------------------------------------------------------------------------------------------

function ListAccounts(knownAccounts)

    local accountNumber = overview_html:xpath("//p[text()='Kundennummer:']/span"):text();
    -- Supports only one account
    local account = {
        owner = overview_html:xpath("//*/p[@class='welcome-msg']/strong"):text(),
        name = "Paypack Punkte Konto (" .. accountNumber .. ")",
        accountNumber = accountNumber,
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
    overview_html:xpath("//input[@id='date1']"):attr("value", os.date("%d.%m.%Y", since))
    overview_html:xpath("//input[@id='date2']"):attr("value", os.date("%d.%m.%Y"))

    MM.printStatus("Fill in date ranges")

    print("Submitting transaction search form for " .. account.accountNumber)
    overview_html = HTML(connection:request(overview_html:xpath("//form[@id='pointRangeForm']"):submit()))

    -- Get paypack points from text next to select box
    local balance = overview_html:xpath("//span[@id='serverPoints']"):text()
    -- eleminate the dot in the point number and divide it with 100 to get the euro equivalent
    balance = string.gsub(balance,"%.","")/100

    MM.printStatus("balance " .. balance)

    local firstPage =true;

    repeat
        local noMorePages = true;

        -- Check if the HTML table with transactions exists.
        if overview_html:xpath("//table[@class='mypoints']/tbody/tr[1]/td[1]"):length() > 0 then

            -- Extract transactions.
            overview_html:xpath("//table[@class='mypoints']/tbody/tr[position()>0]"):each(function (index, row)
                local columns = row:children()
                local transaction = {
                    valueDate   = strToFullDate(columns:get(1):text()),
                    bookingDate = strToFullDate(columns:get(1):text()),
                    name        = columns:get(2):text(),
                    purpose     = columns:get(3):text() .. " : " .. columns:get(4):text(), true,
                    currency    = "EUR",
                    amount      = strToAmount(columns:get(4):text(), true)/100
                }

                table.insert(transactions, transaction)
            end)


            local linkCounter
            if firstPage then
                linkCounter = 1
            else
                linkCounter = 2
            end


            local nextPageLink = overview_html:xpath("//div[@class='pager-list']/a[".. linkCounter .."]");

            -- check website for more pages to extract transactions for
            if  nextPageLink:length()> 0 then
                local link = overview_html:xpath("//div[@class='pager-list']/a[".. linkCounter .."]")
                overview_html = HTML(connection:request(overview_html:xpath("//div[@class='pager-list']/a[".. linkCounter .."]"):click()))
                noMorePages = false;
                firstPage=false;
                MM.printStatus("Getting more transactions...")
            end

        end
    until (noMorePages);

    -- Return balance and array of transactions.
    return {balance=balance, transactions=transactions, securities=nil}
end

-- ---------------------------------------------------------------------------------------------------------------------

function EndSession()

    -- Submit logout form.
    local logout_html = HTML(connection:request(overview_html:xpath("//a[@id='pbLogin']"):click()))

    print("Logged out successfully!")
end
