-- Migration 029: company changes
--
-- Acquisitions, mergers and renames the analysis models may not know about
-- (DEVELOPMENT_JOURNAL.md 2.31-2.34, 2.76). When a story names one of a
-- record's keywords, the record goes into the analysis prompt as one line.
--
-- 1. company_changes: one row per version of a record. A version is never
--    edited: replace_company_change closes the current one (superseded_at) and
--    inserts the next in the same transaction, so the rows the prompt could use
--    at time t are those with recorded_at <= t < superseded_at (or no
--    superseded_at). announced_on and effective_on are when it happened.
--      kind  acquires     the asset buys party
--            acquired_by  party buys the asset
--            renamed      party is the former name, new_name the current one
--    effective_on is the day a deal closed or was terminated, or a rename took
--    effect; a pending deal has none. asset_symbol follows rename_asset through
--    ON UPDATE CASCADE. keywords: a story naming one gets the line; one written
--    in capitals (a ticker) matches only in capitals. recorded_by is 'seed' or
--    the model that verified the record; source_article_id the story that set
--    it off.
-- 2. articles.changes_pending_since: a package story that reads like a deal or
--    a rename waits for the model here, like topics_pending_since.
-- 3. The seed: the 2026-10-22 web scan (~/Desktop/seed_scan, 78 changes) with
--    the closing dates corrected in 2.34 (RPMGlobal, Halda, Orbital), Toncoin
--    moved to GRAM-USD, and Contentful, Braze, Sundyne, CAES, Nvidia-Hugging
--    Face (missed by the scan) and Intel-Classiq (signed after it) added.
--    Salesforce-Fin stays completed: Salesforce announced the closing on
--    2026-09-10, ahead of the expected date that 2.34 went by. Keywords were
--    chosen by hand: no ordinary words (Own, Pioneer, Orbital), no tickers of
--    delisted companies, nothing shorter than three letters.
--
-- company_changes is reached only through the service role: RLS is on with no
-- policies. Apply before starting the new backend: it writes
-- articles.changes_pending_since.

BEGIN;

CREATE TABLE company_changes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_symbol TEXT NOT NULL REFERENCES assets(symbol) ON UPDATE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('acquires', 'acquired_by', 'renamed')),
    party TEXT NOT NULL CHECK (party <> ''),
    new_name TEXT,
    status TEXT NOT NULL CHECK (status IN ('pending', 'completed', 'terminated')),
    announced_on DATE,
    effective_on DATE,
    keywords TEXT[] NOT NULL CHECK (cardinality(keywords) > 0),
    sources TEXT[] NOT NULL DEFAULT '{}',
    recorded_by TEXT NOT NULL,
    source_article_id UUID REFERENCES articles(id) ON DELETE SET NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    superseded_at TIMESTAMPTZ,
    CHECK ((kind = 'renamed') = (new_name IS NOT NULL)),
    CHECK (kind <> 'renamed' OR status = 'completed'),
    CHECK ((status = 'pending') = (effective_on IS NULL)),
    CHECK (status = 'completed' OR announced_on IS NOT NULL)
);

CREATE UNIQUE INDEX company_changes_current
    ON company_changes (asset_symbol, kind, lower(party)) WHERE superseded_at IS NULL;

ALTER TABLE company_changes ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION replace_company_change(
    p_old UUID,
    p_status TEXT,
    p_effective_on DATE,
    p_sources TEXT[],
    p_recorded_by TEXT,
    p_article UUID
)
RETURNS UUID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_id UUID;
BEGIN
    UPDATE company_changes SET superseded_at = NOW() WHERE id = p_old AND superseded_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'company change % is not current', p_old;
    END IF;

    INSERT INTO company_changes (
        asset_symbol, kind, party, new_name, status, announced_on, effective_on,
        keywords, sources, recorded_by, source_article_id
    )
    SELECT asset_symbol, kind, party, new_name, p_status, announced_on, p_effective_on,
        keywords, p_sources, p_recorded_by, p_article
    FROM company_changes WHERE id = p_old
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION replace_company_change(UUID, TEXT, DATE, TEXT[], TEXT, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION replace_company_change(UUID, TEXT, DATE, TEXT[], TEXT, UUID) TO service_role;

ALTER TABLE articles ADD COLUMN changes_pending_since TIMESTAMPTZ;
CREATE INDEX idx_articles_changes_pending ON articles (changes_pending_since)
    WHERE changes_pending_since IS NOT NULL;

INSERT INTO company_changes (
    asset_symbol, kind, party, new_name, status, announced_on, effective_on, keywords, sources, recorded_by
)
VALUES
    ('ABBV', 'acquires', 'Aliada Therapeutics', NULL, 'completed', '2024-10-29', '2024-12-11', ARRAY['Aliada Therapeutics'], ARRAY['https://www.nasdaq.com/articles/abbvie-agrees-acquire-aliada-therapeutics-14-bln-cash', 'https://www.dcatvci.org/top-industry-news/abbvie-completes-1-4-bn-acquisition-of-aliada-therapeutics/'], 'seed'),
    ('ABBV', 'acquires', 'Apogee Therapeutics', NULL, 'completed', '2026-06-18', '2026-09-03', ARRAY['Apogee Therapeutics'], ARRAY['https://pulse2.com/abbvie-completes-10-9-billion-acquisition-of-apogee-therapeutics/', 'https://www.rttnews.com/3688302/abbvie-completes-10-9-bln-acquisition-of-apogee-therapeutics.aspx'], 'seed'),
    ('ABBV', 'acquires', 'Capstan Therapeutics', NULL, 'completed', '2025-06-30', '2025-08-19', ARRAY['Capstan Therapeutics'], ARRAY['https://www.cnbc.com/2025/06/30/abbvie-to-buy-capstan-therapeutics.html', 'https://www.nasdaq.com/articles/abbvie-finalizes-acquisition-capstan-therapeutics'], 'seed'),
    ('ABBV', 'acquires', 'Cerevel Therapeutics', NULL, 'completed', '2023-12-06', '2024-08-01', ARRAY['Cerevel'], ARRAY['https://news.abbvie.com/2024-08-01-AbbVie-Completes-Acquisition-of-Cerevel-Therapeutics', 'https://pubs.acs.org/doi/10.1021/cen-10141-buscon16'], 'seed'),
    ('ABBV', 'acquires', 'ImmunoGen', NULL, 'completed', '2023-11-30', '2024-02-12', ARRAY['ImmunoGen'], ARRAY['https://www.fiercebiotech.com/biotech/all-abbvie-ceo-richard-gonzalez-wanted-christmas-was-cerevel-wrapped-45-share', 'https://www.sec.gov/Archives/edgar/data/1551152/000155115226000008/abbv-20251231.htm'], 'seed'),
    ('ABBV', 'acquires', 'Landos Biopharma', NULL, 'completed', '2024-03-25', '2024-05-23', ARRAY['Landos'], ARRAY['https://news.abbvie.com/2024-05-23-AbbVie-Completes-Acquisition-of-Landos-Biopharma', 'https://www.paulweiss.com/insights/client-news/abbvie-to-acquire-landos-biopharma'], 'seed'),
    ('ABT', 'acquires', 'Exact Sciences', NULL, 'completed', '2025-11-19', '2026-03-23', ARRAY['Exact Sciences'], ARRAY['https://finance.yahoo.com/sectors/healthcare/articles/abbott-laboratories-abt-announces-completion-155039714.html', 'https://www.investing.com/news/sec-filings/abbott-completes-21-billion-acquisition-of-exact-sciences-delisting-exas-from-nasdaq-93CH-4575370'], 'seed'),
    ('ADBE', 'acquires', 'Semrush', NULL, 'completed', '2025-11-19', '2026-04-28', ARRAY['Semrush'], ARRAY['https://www.semrush.com/news/435826-adobe-to-acquire-semrush/', 'https://pulse2.com/adobe-completes-acquisition-of-semrush-expanding-brand-visibility-and-ai-search-capabilities/amp/'], 'seed'),
    ('AMD', 'acquires', 'ZT Systems', NULL, 'completed', '2024-08-19', '2025-03-31', ARRAY['ZT Systems'], ARRAY['https://ir.amd.com/news-events/press-releases/detail/1240/amd-completes-acquisition-of-zt-systems', 'https://www.sec.gov/Archives/edgar/data/2488/000119312524202457/d808469dex991.htm'], 'seed'),
    ('AMZN', 'acquires', 'iRobot', NULL, 'terminated', '2022-08-05', '2024-01-29', ARRAY['iRobot'], ARRAY['https://aboutamazon.com/news/company-news/amazon-irobot-terminate-acquisition', 'https://www.retail-insight-network.com/news/amazon-irobot-terminate-acquisition/'], 'seed'),
    ('BA', 'acquires', 'Spirit AeroSystems', NULL, 'completed', '2024-07-01', '2025-12-08', ARRAY['Spirit AeroSystems', 'Spirit Aero'], ARRAY['https://investors.boeing.com/investors/news/press-release-details/2025/Boeing-Completes-Acquisition-of-Spirit-AeroSystems/default.aspx', 'https://www.theengineer.co.uk/content/news/boeing-to-acquire-spirit-aerosystems-for-47bn'], 'seed'),
    ('BLK', 'acquires', 'Global Infrastructure Partners', NULL, 'completed', '2024-01-12', '2024-10-01', ARRAY['Global Infrastructure Partners', 'GIP'], ARRAY['https://www.blackrock.com/corporate/newsroom/media/press-releases/blackrock-completes-acquisition-of-global-infrastructure-partners', 'https://axios.com/2024/01/12/blackrock-bigger-global-infrastructure-partners'], 'seed'),
    ('BLK', 'acquires', 'HPS Investment Partners', NULL, 'completed', '2024-12-03', '2025-07-01', ARRAY['HPS Investment Partners', 'HPS'], ARRAY['https://www.sec.gov/Archives/edgar/data/2012383/000119312525153573/d78785dex991.htm', 'https://pe-insights.com/blackrock-finalises-hps-acquisition-to-launch-190bn-private-credit-platform/'], 'seed'),
    ('BLK', 'acquires', 'Preqin', NULL, 'completed', '2024-06-30', '2025-03-03', ARRAY['Preqin'], ARRAY['https://www.blackrock.com/corporate/newsroom/media/press-releases/blackrock-completes-preqin-acquisition', 'https://www.alternativeswatch.com/2024/07/01/blackrock-acquiring-alts-data-provider-preqin-for-3-2bn/'], 'seed'),
    ('BMY', 'acquires', '2seventy bio', NULL, 'completed', '2025-03-10', '2025-05-13', ARRAY['2seventy'], ARRAY['https://www.americanpharmaceuticalreview.com/1315-News/618163-2seventy-bio-to-Be-Acquired-by-Bristol-Myers-Squibb/', 'https://www.sec.gov/Archives/edgar/data/14272/000001427225000149/bmy-20250930.htm'], 'seed'),
    ('BMY', 'acquires', 'Karuna Therapeutics', NULL, 'completed', '2023-12-22', '2024-03-18', ARRAY['Karuna'], ARRAY['https://www.businesswire.com/news/home/20240318509649/en/Bristol-Myers-Squibb-Completes-Acquisition-of-PureTechs-Founded-Entity-Karuna-Therapeutics-for-14-Billion', 'https://www.tipranks.com/news/the-fly/bristol-myers-to-acquire-karuna-therapeutics-for-330-per-share-in-cash-2'], 'seed'),
    ('BMY', 'acquires', 'Mirati Therapeutics', NULL, 'completed', '2023-10-08', '2024-01-23', ARRAY['Mirati'], ARRAY['https://www.businesswire.com/news/home/20240122035431/en/Bristol-Myers-Squibb-Completes-Acquisition-of-Mirati-Therapeutics-Strengthening-and-Diversifying-Oncology-Portfolio', 'https://www.roi-nj.com/2024/01/23/healthcare/bristol-myers-squibb-completes-acquisition-of-mirati-therapeutics-strengthening-oncology-portfolio/'], 'seed'),
    ('BMY', 'acquires', 'Orbital Therapeutics', NULL, 'completed', '2025-10-10', '2025-12-08', ARRAY['Orbital Therapeutics'], ARRAY['https://www.indianpharmapost.com/news/lite/bristol-myers-squibb-buys-orbital-therapeutics-for-15-billion-to-strengthen-cell-therapy-portfolio-17986', 'https://www.sec.gov/Archives/edgar/data/14272/000001427226000004/bmy-20251231.htm'], 'seed'),
    ('BMY', 'acquires', 'RayzeBio', NULL, 'completed', '2023-12-26', '2024-02-26', ARRAY['RayzeBio'], ARRAY['https://www.biospace.com/bristol-myers-squibb-completes-acquisition-of-rayzebio-adding-differentiated-actinium-based-radiopharmaceutical-platform', 'https://www.streetinsider.com/entities/Twitter/RYZB'], 'seed'),
    ('CAT', 'acquires', 'RPMGlobal', NULL, 'completed', '2025-10-12', '2026-02-17', ARRAY['RPMGlobal', 'RPM Global'], ARRAY['https://simplywall.st/stocks/de/software/fra-4q3/rpmglobal-holdings-shares/future', 'https://rpmglobal.com/company-update-caterpillar-cat-and-rpm-have-signed-a-binding-scheme-implementation-deed/'], 'seed'),
    ('CRM', 'acquires', 'Braze', NULL, 'pending', '2026-10-20', NULL, ARRAY['Braze', 'BRZE'], ARRAY['https://www.salesforce.com/news/press-releases/2026/10/20/salesforce-signs-definitive-agreement-to-acquire-braze/', 'https://www.sec.gov/Archives/edgar/data/1676238/000095010326015850/dp254600_8k.htm'], 'seed'),
    ('CRM', 'acquires', 'Contentful', NULL, 'completed', '2026-06-01', '2026-09-01', ARRAY['Contentful'], ARRAY['https://www.salesforce.com/news/stories/salesforce-signs-definitive-agreement-to-acquire-contentful/', 'https://www.sec.gov/Archives/edgar/data/1108524/000110852426000190/crm-20260731.htm'], 'seed'),
    ('CRM', 'acquires', 'Fin (formerly Intercom)', NULL, 'completed', '2026-06-15', '2026-09-10', ARRAY['Intercom'], ARRAY['https://www.salesforce.com/news/press-releases/2026/09/10/salesforce-completes-acquisition-of-fin/', 'https://finviz.com/news/390851/salesforce-completes-acquisition-of-fin'], 'seed'),
    ('CRM', 'acquires', 'Informatica', NULL, 'completed', '2025-05-27', '2025-11-18', ARRAY['Informatica'], ARRAY['https://markets.financialcontent.com/clarkebroadcasting.mymotherlode/article/bizwire-2025-11-18-salesforce-completes-acquisition-of-informatica', 'https://news.bloomberglaw.com/tech-and-telecom-law/salesforce-agrees-to-buy-informatica-in-deal-worth-8-billion'], 'seed'),
    ('CRM', 'acquires', 'Own Company', NULL, 'completed', '2024-09-05', '2024-11-18', ARRAY['Own Company', 'OwnBackup'], ARRAY['https://www.salesforce.com/news/press-releases/2024/09/05/salesforce-signs-definitive-agreement-to-acquire-own-company/', 'https://www.calcalistech.com/ctechnews/article/r1zgwzyfyx'], 'seed'),
    ('CSCO', 'acquires', 'Splunk', NULL, 'completed', '2023-09-21', '2024-03-18', ARRAY['Splunk'], ARRAY['https://investor.cisco.com/files/doc_news/Cisco-Completes-Acquisition-of-Splunk-2024.pdf', 'https://siliconangle.com/2024/03/18/cisco-completes-28b-acquisition-splunk/'], 'seed'),
    ('CVX', 'acquires', 'Hess Corporation', NULL, 'completed', '2023-10-23', '2025-07-18', ARRAY['Hess Corporation', 'Hess'], ARRAY['https://worldoil.com/news/2025/7/18/chevron-completes-53-billion-hess-takeover-following-lengthy-exxon-arbitration/', 'https://www.axios.com/2025/07/18/chevron-hess-merger-exxon-ruling'], 'seed'),
    ('GILD', 'acquires', 'Arcellx', NULL, 'completed', '2026-02-23', '2026-04-28', ARRAY['Arcellx'], ARRAY['https://investors.gilead.com/news/news-details/2026/Gilead-Sciences-Completes-Acquisition-of-Arcellx-Ahead-of-Potential-Commercial-Launch-of-Anito-cel/default.aspx', 'https://www.ropesgray.com/en/news-and-events/news/2026/02/gilead-sciences-to-acquire-biotechnology-company-arcellx'], 'seed'),
    ('GILD', 'acquires', 'CymaBay Therapeutics', NULL, 'completed', '2024-02-12', '2024-03-22', ARRAY['CymaBay'], ARRAY['https://www.nasdaq.com/press-release/gilead-sciences-announces-completion-of-acquisition-of-cymabay-2024-03-22', 'https://www.tipranks.com/news/m-a-news-gilead-nasdaqgild-snaps-up-cymabay-nasdaqcbay-for-32-50-per-share'], 'seed'),
    ('GOOGL', 'acquires', 'Intersect Power', NULL, 'completed', '2025-12-22', '2026-03-10', ARRAY['Intersect Power'], ARRAY['https://9to5google.com/2025/12/22/alphabet-acquiring-intersect/', 'https://www.sec.gov/Archives/edgar/data/0001652044/000165204426000048/goog-20260331.htm'], 'seed'),
    ('GOOGL', 'acquires', 'Wiz', NULL, 'completed', '2025-03-18', '2026-03-11', ARRAY['Wiz'], ARRAY['https://abc.xyz/investor/news/news-details/2026/Google-Completes-Acquisition-of-Wiz-2026-ta7OaU2uA0/default.aspx', 'https://www.cybersecuritydive.com/news/google-32-billion-acquisition-wiz/814437/'], 'seed'),
    ('GRAM-USD', 'renamed', 'Toncoin', 'Gram', 'completed', '2026-06-01', '2026-06-15', ARRAY['Toncoin', 'The Open Network', 'TON', 'GRAM'], ARRAY['https://www.kucoin.com/news/flash/ton-native-token-to-be-renamed-gram-on-june-15-2026', 'https://decrypt.co/369660/ton-price-pumps-telegram-ceo-token-rebranded-gram'], 'seed'),
    ('HD', 'acquires', 'GMS Inc.', NULL, 'completed', '2025-06-30', '2025-09-04', ARRAY['GMS Inc'], ARRAY['https://corporate.homedepot.com/news/company/home-depot-and-its-subsidiary-srs-distribution-complete-acquisition-gms', 'https://www.nasdaq.com/articles/home-depot-completes-55-bln-acquisition-gms-through-srs-distribution'], 'seed'),
    ('HD', 'acquires', 'SRS Distribution', NULL, 'completed', '2024-03-28', '2024-06-18', ARRAY['SRS Distribution'], ARRAY['https://www.sec.gov/Archives/edgar/data/354950/000035495024000177/exhibit991-6182024srsclosi.htm', 'https://www.tipranks.com/news/press-releases/the-home-depot-completes-acquisition-of-srs-distribution'], 'seed'),
    ('HON', 'acquires', 'CAES', NULL, 'completed', NULL, '2024-09-04', ARRAY['CAES'], ARRAY['https://www.honeywell.com/us/en/news/press-releases/2024/09/honeywell-completes-acquisition-of-caes', 'https://militaryembedded.com/radar-ew/rf-and-microwave/honeywell-completes-acquisition-of-caes'], 'seed'),
    ('HON', 'acquires', 'Sundyne', NULL, 'completed', NULL, '2025-06-09', ARRAY['Sundyne'], ARRAY['https://www.honeywell.com/us/en/press/2025/06/honeywell-completes-acquisition-of-sundyne-to-expand-process-industry-capabilities', 'https://www.worldpumps.com/content/news/honeywell-completes-acquisition-of-sundyne'], 'seed'),
    ('IBM', 'acquires', 'Confluent', NULL, 'completed', '2025-12-08', '2026-03-17', ARRAY['Confluent'], ARRAY['https://www.stocktitan.net/news/IBM/ibm-completes-acquisition-of-confluent-making-real-time-data-the-lbuwdbharsqe.html', 'https://www.channelweb.co.uk/news-network/2026/ibm-completes-11bn-confluent-acquisition'], 'seed'),
    ('IBM', 'acquires', 'HashiCorp', NULL, 'completed', '2024-04-24', '2025-02-27', ARRAY['HashiCorp'], ARRAY['https://newsroom.ibm.com/2024-04-24-IBM-to-Acquire-HashiCorp-Inc-Creating-a-Comprehensive-End-to-End-Hybrid-Cloud-Platform', 'https://www.techrepublic.com/article/ibm-hashicorp-acquisition-completed/'], 'seed'),
    ('INTC', 'acquires', 'Classiq', NULL, 'pending', '2026-10-26', NULL, ARRAY['Classiq'], ARRAY['https://hlc.com/en/news/hogan-lovells-cadwalader-advises-intel-in-pending-acquisition-of-classiq-technologies', 'https://evertiq.com/design/2026-10-27-intel-to-acquire-quantum-software-company-classiq'], 'seed'),
    ('JNJ', 'acquires', 'Ambrx Biopharma', NULL, 'completed', '2024-01-08', '2024-03-07', ARRAY['Ambrx'], ARRAY['https://www.jnj.com/media-center/press-releases/johnson-johnson-completes-acquisition-of-ambrx', 'https://www.dcatvci.org/top-industry-news/jj-completes-2-bn-acquisition-of-adc-company-ambrx-biopharma/'], 'seed'),
    ('JNJ', 'acquires', 'Firefly Bio', NULL, 'completed', '2026-06-08', '2026-07-29', ARRAY['Firefly Bio'], ARRAY['https://www.sec.gov/Archives/edgar/data/0000200406/000020040626000163/jnj-20260729.htm', 'https://www.1stoncology.com/blog/?p=112507'], 'seed'),
    ('JNJ', 'acquires', 'Halda Therapeutics', NULL, 'completed', '2025-11-17', '2025-12-29', ARRAY['Halda'], ARRAY['https://www.jnj.com/media-center/press-releases/johnson-johnson-completes-acquisition-of-halda-therapeutics-and-its-novel-platform-to-revolutionize-cancer-treatment-and-enable-next-generation-oral-therapies', 'https://healthcare.levinassociates.com/2025/11/17/johnson-johnson-acquires-halda-therapeutics-for-3-05-billion/'], 'seed'),
    ('JNJ', 'acquires', 'Intra-Cellular Therapies', NULL, 'completed', '2025-01-13', '2025-04-02', ARRAY['Intra-Cellular'], ARRAY['https://www.sec.gov/Archives/edgar/data/200406/000020040625000178/jnj-20250629.htm', 'https://www.tipranks.com/news/the-fly/johnson-johnson-completes-intra-cellular-therapies-acquisition-sees-dilution'], 'seed'),
    ('JNJ', 'acquires', 'Shockwave Medical', NULL, 'completed', '2024-04-05', '2024-05-31', ARRAY['Shockwave Medical'], ARRAY['https://www.jnj.com/media-center/press-releases/johnson-johnson-completes-acquisition-of-shockwave-medical', 'https://cardiovascularbusiness.com/topics/clinical/interventional-cardiology/its-official-johnson-johnson-completes-13b-shockwave-medical-acquisition'], 'seed'),
    ('LLY', 'acquires', 'Adverum Biotechnologies', NULL, 'completed', '2025-10-24', '2025-12-09', ARRAY['Adverum'], ARRAY['https://investor.lilly.com/node/53521', 'https://www.sec.gov/Archives/edgar/data/1501756/000119312525311997/d14417dex99a5b.htm'], 'seed'),
    ('LLY', 'acquires', 'AtaiBeckley', NULL, 'completed', '2026-07-17', '2026-09-11', ARRAY['AtaiBeckley', 'atai Life Sciences', 'Beckley Psytech'], ARRAY['https://parameter.io/eli-lilly-lly-finalizes-2-8b-ataibeckley-acquisition-for-mental-health-pipeline/', 'https://nasdaq.com/articles/lilly-agrees-acquire-ataibeckley-upto-38-bln-cash'], 'seed'),
    ('LLY', 'acquires', 'Centessa Pharmaceuticals', NULL, 'completed', '2026-03-31', '2026-06-24', ARRAY['Centessa'], ARRAY['https://www.sec.gov/Archives/edgar/data/0001847903/000119312526280337/d150381d8k.htm', 'https://www.rttnews.com/3662435/lilly-completes-acquisition-of-centessa-pharma-for-expansion-into-sleep-medicine.aspx'], 'seed'),
    ('LLY', 'acquires', 'Kelonia Therapeutics', NULL, 'pending', '2026-04-20', NULL, ARRAY['Kelonia'], ARRAY['https://www.financierworldwide.com/eli-lilly-to-acquire-kelonia-therapeutics-for-7bn', 'https://pharmashots.com/32870/eli-lilly-to-acquire-kelonia-therapeutics-for-7b/'], 'seed'),
    ('LLY', 'acquires', 'Merida Biosciences', NULL, 'pending', '2026-08-31', NULL, ARRAY['Merida Biosciences'], ARRAY['https://www.contractpharma.com/breaking-news/lilly-to-acquire-merida-biosciences-for-2-875b/', 'https://www.pharmexec.com/view/eli-lilly-acquire-merida-biosciences-2-billion'], 'seed'),
    ('LLY', 'acquires', 'Morphic Holding', NULL, 'completed', '2024-07-08', '2024-08-16', ARRAY['Morphic Holding', 'Morphic Therapeutic', 'Morphic Therapeutics'], ARRAY['https://investor.lilly.com/news-releases/news-release-details/lilly-completes-acquisition-morphic-improve-outcomes-and-expand', 'https://www.pharmaceutical-technology.com/news/lilly-concludes-morphic-acquisition/'], 'seed'),
    ('LLY', 'acquires', 'Orna Therapeutics', NULL, 'pending', '2026-02-09', NULL, ARRAY['Orna Therapeutics'], ARRAY['https://www.fiercebiotech.com/biotech/lilly-buys-orna-24b-enter-vivo-car-t-arena', 'https://pulse2.com/eli-lilly-to-acquire-orna-therapeutics-in-up-to-2-4-billion-deal/'], 'seed'),
    ('LLY', 'acquires', 'Ventyx Biosciences', NULL, 'completed', '2026-01-07', '2026-03-04', ARRAY['Ventyx'], ARRAY['https://www.sec.gov/Archives/edgar/data/1851194/000119312526090059/d116049d8k.htm', 'https://pmlive.com/pharma_news/lilly-announces-acquisition-of-ventyx-biosciences-for-around-1-2bn/'], 'seed'),
    ('LLY', 'acquires', 'Verve Therapeutics', NULL, 'completed', '2025-06-17', '2025-07-25', ARRAY['Verve Therapeutics'], ARRAY['https://www.biospace.com/press-releases/lilly-completes-acquisition-of-verve-therapeutics-to-advance-one-time-treatments-for-people-with-high-cardiovascular-risk', 'https://www.nasdaq.com/articles/lilly-completes-acquisition-verve-therapeutics'], 'seed'),
    ('LMT', 'acquires', 'Terran Orbital', NULL, 'completed', '2024-08-15', '2024-10-30', ARRAY['Terran Orbital'], ARRAY['https://intelligencecommunitynews.com/lockheed-martin-completes-terran-orbital-acquisition/', 'https://satelliteprome.com/news/lockheed-martin-acquires-smallsat-manufacturer-terran-orbital/'], 'seed'),
    ('MA', 'acquires', 'Recorded Future', NULL, 'completed', '2024-09-12', '2024-12-20', ARRAY['Recorded Future'], ARRAY['https://www.mastercard.com/au/en/news-and-trends/press/2024/december/mastercard-finalizes-acquisition-of-recorded-future.html', 'https://www.bostonglobe.com/2024/09/12/business/mastercard-recorded-future-acquisition-cybersecurity'], 'seed'),
    ('MRK', 'acquires', 'Cidara Therapeutics', NULL, 'completed', '2025-11-14', '2026-01-07', ARRAY['Cidara'], ARRAY['https://www.merck.com/news/merck-to-complete-acquisition-of-cidara-therapeutics/', 'https://www.americanpharmaceuticalreview.com/1315-News/622763-Merck-to-Acquire-Cidara-Therapeutics-in-9-2B-Deal/'], 'seed'),
    ('MRK', 'acquires', 'EyeBio', NULL, 'completed', '2024-05-29', '2024-07-12', ARRAY['EyeBio', 'Eyebiotech'], ARRAY['https://www.merck.com/news/merck-to-acquire-eyebio', 'https://businesswire.com/news/home/20240712972802/en/Merck-Completes-Acquisition-of-EyeBio'], 'seed'),
    ('MRK', 'acquires', 'Harpoon Therapeutics', NULL, 'completed', '2024-01-08', '2024-03-11', ARRAY['Harpoon Therapeutics'], ARRAY['https://www.merck.com/news/merck-completes-acquisition-of-harpoon-therapeutics-inc/', 'https://www.pharmaceutical-technology.com/news/merck-completes-harpoon-acquisition/'], 'seed'),
    ('MRK', 'acquires', 'Terns Pharmaceuticals', NULL, 'completed', '2026-03-25', '2026-05-05', ARRAY['Terns Pharmaceuticals'], ARRAY['https://www.merck.com/?p=3690505', 'https://www.roi-nj.com/2026/05/05/healthcare/merck-completes-purchase-of-terns-pharmaceuticals-inc/'], 'seed'),
    ('MRK', 'acquires', 'Verona Pharma', NULL, 'completed', '2025-07-09', '2025-10-07', ARRAY['Verona Pharma'], ARRAY['https://www.msd.com/news/msd-completes-acquisition-of-verona-pharma/', 'https://finance.yahoo.com/news/merck-completes-10b-acquisition-verona-132852234.html'], 'seed'),
    ('NEE', 'acquires', 'Dominion Energy', NULL, 'pending', '2026-05-18', NULL, ARRAY['Dominion Energy'], ARRAY['https://www.sec.gov/Archives/edgar/data/0000753308/000110465926063001/tm2614888d1_8k.htm', 'https://www.enerdata.net/publications/daily-energy-news/nextera-energy-and-dominion-energy-announce-usd67bn-merger-us.html'], 'seed'),
    ('NFLX', 'acquires', 'Warner Bros. Discovery', NULL, 'terminated', '2025-12-04', '2026-02-27', ARRAY['Warner Bros', 'WBD'], ARRAY['http://about.netflix.com/en/news/netflix-to-acquire-warner-bros', 'https://www.sec.gov/Archives/edgar/data/0001065280/000106528026000212/nflx-20260630.htm'], 'seed'),
    ('NOW', 'acquires', 'Armis', NULL, 'completed', '2025-12-22', '2026-04-20', ARRAY['Armis'], ARRAY['https://www.businesswire.com/news/home/20251222437177/en/ServiceNow-to-acquire-Armis-to-expand-cyber-exposure-and-security-across-the-full-attack-surface-in-IT-OT-and-medical-devices-for-companies-governments-and-critical-infrastructure-worldwide', 'https://intelligencecommunitynews.com/servicenow-completes-armis-acquisition/'], 'seed'),
    ('NOW', 'acquires', 'Moveworks', NULL, 'completed', '2025-03-10', '2025-12-15', ARRAY['Moveworks'], ARRAY['https://techcrunch.com/2025/03/10/servicenow-buys-moveworks-for-2-85b-to-grow-its-ai-portfolio', 'https://investor.servicenow.com/news/news-details/2025/ServiceNow-completes-acquisition-of-Moveworks/'], 'seed'),
    ('NOW', 'acquires', 'Veza', NULL, 'completed', '2025-12-02', '2026-03-02', ARRAY['Veza'], ARRAY['https://www.sec.gov/Archives/edgar/data/0001373715/000137371526000056/now-20260331.htm', 'https://www.securityweek.com/servicenow-to-acquire-identity-security-firm-veza-in-reported-1-billion-deal/'], 'seed'),
    ('NVDA', 'acquires', 'Hugging Face', NULL, 'pending', '2026-09-03', NULL, ARRAY['Hugging Face'], ARRAY['https://semafor.com/article/09/03/2026/nvidia-to-buy-hugging-face-for-nearly-13-billion', 'https://abcnews.com/Business/wireStory/nvidia-buying-artificial-intelligence-platform-hugging-face-13-136169594'], 'seed'),
    ('NVO', 'acquires', 'Akero Therapeutics', NULL, 'completed', '2025-10-09', '2025-12-09', ARRAY['Akero'], ARRAY['https://www.nasdaq.com/press-release/novo-nordisk-has-completed-its-acquisition-akero-therapeutics-2025-12-09', 'https://www.americanpharmaceuticalreview.com/1315-News/621886-Novo-Nordisk-Announces-5-2B-Acquisition-of-Akero-Therapeutics-to-Strengthen-Liver-Disease-Portfolio/'], 'seed'),
    ('PANW', 'acquires', 'Chronosphere', NULL, 'completed', '2025-11-19', '2026-01-29', ARRAY['Chronosphere'], ARRAY['https://investors.paloaltonetworks.com/news-releases/news-release-details/palo-alto-networks-completes-chronosphere-acquisition-unifying', 'https://securityweek.com/palo-alto-networks-to-acquire-observability-platform-chronosphere-in-3-35-billion-deal/'], 'seed'),
    ('PANW', 'acquires', 'CyberArk', NULL, 'completed', '2025-07-30', '2026-02-11', ARRAY['CyberArk'], ARRAY['https://www.sec.gov/Archives/edgar/data/1327567/000119312526045600/d40626dex991.htm', 'https://www.crnasia.com/news-network/2026/palo-alto-networks-completes-25b-acquisition-of-cyberark-for-identity-security-push'], 'seed'),
    ('PEP', 'acquires', 'poppi', NULL, 'completed', '2025-03-17', '2025-05-19', ARRAY['poppi'], ARRAY['https://www.nasdaq.com/press-release/pepsico-completes-acquisition-poppi-accelerating-strategic-portfolio-transformation', 'https://www.foodnavigator-usa.com/Article/2025/03/17/pepsico-snaps-up-fan-favorite-gut-health-soda-brand-poppi/'], 'seed'),
    ('PEP', 'acquires', 'Siete Foods', NULL, 'completed', '2024-10-02', '2025-01-17', ARRAY['Siete Foods'], ARRAY['https://www.sec.gov/Archives/edgar/data/77476/000007747625000019/pep-20250322.htm', 'https://www.vendingtimes.com/news/pepsico-acquires-siete-foods-for-12b/'], 'seed'),
    ('PFE', 'acquires', 'Metsera', NULL, 'completed', '2025-09-22', '2025-11-13', ARRAY['Metsera'], ARRAY['https://pulse2.com/pfizer-buying-metsera-for-up-to-7-3-billion/amp/', 'https://www.sec.gov/Archives/edgar/data/78003/000007800325000159/pfe-20251113.htm'], 'seed'),
    ('PG', 'acquires', 'Thorne HealthTech', NULL, 'pending', '2026-08-04', NULL, ARRAY['Thorne HealthTech', 'Thorne'], ARRAY['https://www.stocktitan.net/news/PG/thorne-enters-into-definitive-agreement-to-be-acquired-by-procter-6gjlbl6d5e8r.html', 'https://www.sahmcapital.com/news/content/procter-gamble-to-acquire-thorne-from-l-cattertons-flagship-fund-deal-anticipated-to-close-later-in-2026-2026-08-04'], 'seed'),
    ('POL28321-USD', 'renamed', 'Polygon (MATIC)', 'POL', 'completed', '2023-09-14', '2024-09-04', ARRAY['Polygon', 'MATIC', 'POL'], ARRAY['https://getblock.io/blog/polygon-matic-becomes-pol/', 'https://www.theblock.co/post/250944/polygon-matic-upgrade'], 'seed'),
    ('QCOM', 'acquires', 'Alphawave Semi', NULL, 'completed', '2025-06-09', '2025-12-18', ARRAY['Alphawave'], ARRAY['https://www.qualcomm.com/news/releases/2025/12/qualcomm-completes-acquisition-of-alphawave-semi', 'https://www.businesswire.com/news/home/20250609911615/en'], 'seed'),
    ('SCHW', 'acquires', 'Forge Global', NULL, 'completed', '2025-11-06', '2026-03-02', ARRAY['Forge Global'], ARRAY['https://pressroom.aboutschwab.com/press-releases/press-release/2026/Charles-Schwab-Completes-Acquisition-of-Forge-Global/', 'https://forgeglobal.com/press-releases/charles-schwab-completes-acquisition-of-forge-global/'], 'seed'),
    ('SYK', 'acquires', 'Inari Medical', NULL, 'completed', '2025-01-06', '2025-02-19', ARRAY['Inari Medical'], ARRAY['https://investors.stryker.com/press-releases/news-details/2025/Stryker-completes-acquisition-of-Inari-Medical-Inc.-providing-entry-into-the-high-growth-peripheral-vascular-segment/default.aspx', 'https://www.massdevice.com/stryker-completes-acquisition-inari-medical/'], 'seed'),
    ('TXN', 'acquires', 'Silicon Labs', NULL, 'pending', '2026-02-04', NULL, ARRAY['Silicon Labs', 'Silicon Laboratories', 'SLAB'], ARRAY['https://www.sec.gov/Archives/edgar/data/0000097476/000009747626000101/txn-20260331.htm', 'https://evertiq.com/summary/2026-02-04-texas-instruments-forvarvar-silicon-labs-for-75-miljarder-dollar'], 'seed'),
    ('UBER', 'acquires', 'Delivery Hero', NULL, 'pending', '2026-07-16', NULL, ARRAY['Delivery Hero'], ARRAY['https://www.bloomberg.com/news/articles/2026-07-16/uber-agrees-to-buy-delivery-hero-as-food-sector-consolidates', 'https://www.sec.gov/Archives/edgar/data/0001543151/000155278126000382/e26302_ex99-1.htm'], 'seed'),
    ('UNH', 'acquires', 'Amedisys', NULL, 'completed', '2023-06-26', '2025-08-14', ARRAY['Amedisys'], ARRAY['https://www.beckerspayer.com/m-and-a/unitedhealth-amedisys-complete-merger/', 'https://www.sec.gov/Archives/edgar/data/896262/000110465923074547/tm2319648d1_ex99-1.htm'], 'seed'),
    ('UPS', 'acquires', 'Andlauer Healthcare Group', NULL, 'completed', '2025-04-24', '2025-11-01', ARRAY['Andlauer'], ARRAY['https://pulse2.com/ups-1-6-billion-acquisition-of-andlauer-healthcare-group-completed', 'https://seekingalpha.com/pr/20077562-andlauer-healthcare-group-to-be-acquired-by-ups'], 'seed'),
    ('V', 'acquires', 'BioCatch', NULL, 'pending', '2026-08-03', NULL, ARRAY['BioCatch'], ARRAY['https://www.fintechfutures.com/m-a/visa-acquires-biocatch', 'https://news.bloomberglaw.com/tech-and-telecom-law/visa-to-buy-fraud-prevention-firm-biocatch-for-2-4-billion-1'], 'seed'),
    ('WMT', 'acquires', 'Vizio', NULL, 'completed', '2024-02-20', '2024-12-03', ARRAY['Vizio'], ARRAY['https://talkbusiness.net/2024/12/walmart-completes-2-3-billion-acquisition-of-vizio/', 'https://www.cepro.com/news/walmart-acquires-vizio-for-2-3-billion/'], 'seed'),
    ('XOM', 'acquires', 'Pioneer Natural Resources', NULL, 'completed', '2023-10-11', '2024-05-03', ARRAY['Pioneer Natural Resources'], ARRAY['https://www.sec.gov/Archives/edgar/data/34088/000095010324006322/dp210867_8k.htm', 'https://benzinga.com/markets/equities/23/10/35190543/its-official-exxon-mobil-to-acquire-pioneer-natural-resources-for-59-5b-in-stock'], 'seed');

COMMIT;
