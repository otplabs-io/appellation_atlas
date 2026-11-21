"""Rivers and lakes on the globe: only the ones the pages name, so the map shows what the words point at (the Gironde between
the Left and Right Banks, the Breede through its wards, Clear Lake in its AVAs).

  python src/water.py fetch   asks OpenStreetMap's Overpass API for each one's lines or outline, over the views that show it
                              (data/cache/water/<id>.json; about 150 small queries, a second apart)
  python src/water.py list    which pages name which river or lake

atlas.py geo calls attach(), which puts each view's rivers and lakes into its view file, clipped to the view and thinned to what
its closest zoom can draw. Geometry: OpenStreetMap contributors, ODbL."""
import collections,glob,json,os,re,sys,time,urllib.parse,urllib.request
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
CACHE=os.path.join(ROOT,'data','cache','water')
SRC=dict(name='OpenStreetMap contributors, rivers and lakes named on the page (Overpass API), ODbL 1.0',url='https://www.openstreetmap.org/copyright')

# (id, name shown, words in a page that name it, OpenStreetMap name pattern, kind, reach)
# kind: river (waterway=river), stream (river or stream), lake (natural=water). reach: 'far' fetches it across every view that
# shows it (a long river is drawn along its wine stretch); 'near' only around the places that name it, since names like Dry
# Creek repeat across a county.
R,S,L='river','stream','lake'
GAZ=[
 # France
 ('garonne','Garonne',r'\bGaronne\b',r'^(La )?Garonne$',R,'far'),
 ('dordogne','Dordogne',r'\bDordogne\b',r'^(La )?Dordogne$',R,'far'),
 ('gironde','Gironde',r'\bGironde (estuary|Estuary)\b|\bthe Gironde\b',r'^(La |L.[Ee]stuaire de la )?Gironde$',R,'far'),
 ('loire','Loire',r'(?<![-])\bLoire\b|\briver Loire\b',r'^(La )?Loire$',R,'far'),
 ('rhone','Rhône',r'(?<![-])\bRhône\b(?!-style| varieties| grapes| blend)|\bthe Rhône\b',r'^(Le )?Rh[ôo]ne$',R,'far'),
 ('saone','Saône',r'\bSaône\b',r'^(La )?Sa[ôo]ne$',R,'far'),
 ('aude','Aude',r'\bthe Aude\b|\bAude (river|River|valley)\b',r'^(L.)?Aude$',R,'far'),
 ('charente','Charente',r'\bthe Charente\b|\bCharente (river|River)\b',r'^(La )?Charente$',R,'far'),
 ('yonne','Yonne',r'\bthe Yonne\b',r'^(L.)?Yonne$',R,'far'),
 ('serein','Serein',r'\bSerein\b',r'^(Le )?Serein$',R,'near'),
 ('ardeche','Ardèche',r'\bthe Ardèche\b',r'^(L.)?Ardèche$',R,'far'),
 ('allier','Allier',r'\bthe Allier\b|\bAllier (river|River)\b',r'^(L.)?Allier$',R,'far'),
 ('sevre-nantaise','Sèvre Nantaise',r'\bSèvre\b',r'^(La )?Sèvre Nantaise$',R,'near'),
 ('maine-fr','Maine',r'\bthe Maine\b(?! state)',r'^(La )?Maine$',R,'near'),
 ('layon','Layon',r'\bLayon\b',r'^(Le )?Layon$',R,'near'),
 ('lot','Lot',r'\bthe Lot\b(?! department)|\bLot (river|River|valley)\b',r'^(Le )?Lot$',R,'far'),
 ('tarn','Tarn',r'\bthe Tarn\b(?! department)|\bTarn (river|River)\b',r'^(Le )?Tarn$',R,'far'),
 ('cher','Cher',r'\bthe Cher\b|\bCher (river|River|valley)\b',r'^(Le )?Cher$',R,'far'),
 ('vienne','Vienne',r'\bthe Vienne\b|\bVienne (river|River)\b',r'^(La )?Vienne$',R,'far'),
 ('indre','Indre',r'\bthe Indre\b',r'^(L.)?Indre$',R,'far'),
 ('marne','Marne',r'\bthe Marne\b|\bMarne (river|River|valley)\b|\bVallée de la Marne\b',r'^(La )?Marne$',R,'far'),
 ('seine','Seine',r'\bthe Seine\b',r'^(La )?Seine$',R,'far'),
 ('aube','Aube',r'\bthe Aube\b|\bAube (river|River)\b',r'^(L.)?Aube$',R,'far'),
 ('mauvaise','Mauvaise',r'\bMauvaise\b',r'^(La )?Mauvaise$',S,'near'),
 ('isle','Isle',r'\bthe Isle\b|\bIsle (river|River)\b',r'^(L.)?Isle$',R,'near'),
 ('ciron','Ciron',r'\bCiron\b',r'^(Le )?Ciron$',S,'near'),
 ('herault','Hérault',r'\bthe Hérault\b|\bHérault (river|River|valley)\b',r'^(L.)?Hérault$',R,'far'),
 ('orb','Orb',r'\bthe Orb\b|\bOrb (river|River|valley)\b',r'^(L.)?Orb$',R,'far'),
 ('durance','Durance',r'\bDurance\b',r'^(La )?Durance$',R,'far'),
 ('drome','Drôme',r'\bthe Drôme\b(?! department)',r'^(La )?Drôme$',R,'far'),
 ('adour','Adour',r'\bAdour\b',r'^(L.)?Adour$',R,'far'),
 ('moselle','Moselle',r'\bMoselle\b|\bMosel\b(?!-)',r'^(La )?Moselle$|^Mosel$',R,'far'),
 ('rhine','Rhine',r'\bRhine\b(?!-)|\bRhein\b(?!hessen|gau|-)|\bthe Rhin\b',r'^(Le )?Rhin$|^Rhein$|^Rhine$|^Hochrhein$|^Oberrhein$|^Niederrhein$|^Mittelrhein$|^Alpenrhein$',R,'far'),
 ('ill','Ill',r'\bthe Ill\b',r'^(L.)?Ill$',R,'near'),
 # Germany, Austria, central Europe
 ('ahr','Ahr',r'\bthe Ahr\b|\bAhr (river|River|valley)\b',r'^Ahr$',R,'far'),
 ('nahe','Nahe',r'\bthe Nahe\b|\bNahe (river|River)\b',r'^Nahe$',R,'far'),
 ('main','Main',r'\bthe Main\b(?! Divide| Range| [a-z])|\bMain (river|River|valley)\b',r'^Main$',R,'far'),
 ('saar','Saar',r'\bthe Saar\b|\bSaar (river|River)\b',r'^(Saar|La Sarre)$',R,'far'),
 ('ruwer','Ruwer',r'\bRuwer\b',r'^Ruwer$',R,'near'),
 ('neckar','Neckar',r'\bNeckar\b',r'^Neckar$',R,'far'),
 ('elbe','Elbe',r'\bElbe\b',r'^(Elbe|Labe)$',R,'far'),
 ('saale','Saale',r'\bSaale\b',r'^Saale$',R,'far'),
 ('unstrut','Unstrut',r'\bUnstrut\b',r'^Unstrut$',R,'far'),
 ('danube','Danube',r'\bDanube\b|\bDonau\b|\bthe Duna\b',r'^(Donau|Duna|Dunaj|Dunav|Дунав|Dunărea|Danube)$',R,'far'),
 ('kamp','Kamp',r'\bthe Kamp\b|\bKamp (river|River)\b',r'^Kamp$',R,'near'),
 ('krems','Krems',r'\bthe Krems\b|\bKrems (river|River)\b',r'^Krems$',R,'near'),
 ('traisen','Traisen',r'\bTraisen (river|River)\b|\bthe Traisen\b',r'^Traisen$',R,'near'),
 ('drava','Drava',r'\bDrava\b|\bDrau\b',r'^(Drau|Drava|Dráva)$',R,'far'),
 ('mur','Mur',r'\bthe Mur\b|\bMura\b',r'^(Mur|Mura)$',R,'far'),
 ('tisza','Tisza',r'\bTisza\b',r'^(Tisza|Tisa)$',R,'far'),
 ('bodrog','Bodrog',r'\bBodrog\b',r'^Bodrog$',R,'far'),
 ('neusiedler-see','Lake Neusiedl',r'\bNeusiedl(er ?[Ss]ee)?\b|\bLake Neusiedl\b',r'Neusiedler See|Fertő',L,'far'),
 ('balaton','Lake Balaton',r'\bBalaton\b',r'^Balaton$',L,'far'),
 ('lake-geneva','Lake Geneva',r'\bLake Geneva\b|\bLac Léman\b|\bLake Léman\b',r'^(Lac Léman|Léman|Lac de Genève)$',L,'far'),
 ('lake-neuchatel','Lake Neuchâtel',r'\bLake Neuchâtel\b',r'^Lac de Neuchâtel$',L,'far'),
 ('lake-constance','Lake Constance',r'\bLake Constance\b|\bBodensee\b',r'^Bodensee$',L,'far'),
 ('lake-zurich','Lake Zurich',r'\bLake Zurich\b',r'^Zürichsee$',L,'far'),
 # Italy
 ('po','Po',r'\bthe Po\b|\bPo (river|River|valley|Valley|plain)\b',r'^Po$|^Fiume Po$',R,'far'),
 ('tanaro','Tanaro',r'\bTanaro\b',r'^(Fiume )?Tanaro$',R,'far'),
 ('adige','Adige',r'\bAdige\b(?!-)',r'^(Fiume )?Adige$|^Etsch$',R,'far'),
 ('piave','Piave',r'\bPiave\b',r'^(Fiume )?Piave$',R,'far'),
 ('tagliamento','Tagliamento',r'\bTagliamento\b',r'^(Fiume )?Tagliamento$',R,'far'),
 ('isonzo','Isonzo',r'\bIsonzo\b|\bSoča\b',r'^(Isonzo|Soča)$',R,'far'),
 ('arno','Arno',r'\bArno\b',r'^(Fiume )?Arno$',R,'far'),
 ('tiber','Tiber',r'\bTiber\b|\bTevere\b',r'^(Fiume )?Tevere$',R,'far'),
 ('garda','Lake Garda',r'\bLake Garda\b|\bLago di Garda\b|\bGarda\b(?! DOC)',r'^Lago di Garda$|^Lago di Garda o Benaco$|^Benaco$',L,'far'),
 ('iseo','Lake Iseo',r'\bLake Iseo\b|\bLago d.Iseo\b',r'^Lago d.Iseo$|^Sebino$',L,'far'),
 ('caldaro','Lake Caldaro',r'\bKalterer ?[Ss]ee\b|\bLago di Caldaro\b|\bLake Caldaro\b',r'^Lago di Caldaro|^Kalterer See',L,'near'),
 ('trasimeno','Lake Trasimeno',r'\bTrasimeno\b',r'^Lago Trasimeno$',L,'far'),
 ('bolsena','Lake Bolsena',r'\bBolsena\b',r'^Lago di Bolsena$',L,'far'),
 # Spain and Portugal
 ('duero','Douro',r'\bDuero\b|\bDouro (river|River)\b|\bthe Douro\b',r'^(Duero|Douro|Rio Douro|Río Duero)$',R,'far'),
 ('ebro','Ebro',r'\bEbro\b',r'^(Ebro|Río Ebro|Ebre)$',R,'far'),
 ('tagus','Tagus',r'\bTagus\b|\bthe Tejo\b|\bTajo\b',r'^(Tajo|Tejo|Rio Tejo|Río Tajo)$',R,'far'),
 ('mino','Miño',r'\bMiño\b|\bMinho (river|River)\b',r'^(Miño|Minho|Río Miño|Rio Minho)$',R,'far'),
 ('sil','Sil',r'\bthe Sil\b|\bSil (river|River|canyon)\b',r'^(Río )?Sil$',R,'far'),
 ('pisuerga','Pisuerga',r'\bPisuerga\b',r'^(Río )?Pisuerga$',R,'far'),
 ('arlanza','Arlanza',r'\bArlanza (river|River)\b',r'^(Río )?Arlanza$',R,'near'),
 ('jucar','Júcar',r'\bJúcar\b',r'^(Río )?Júcar$|^Xúquer$',R,'far'),
 ('jiloca','Jiloca',r'\bJiloca\b',r'^(Río )?Jiloca$',R,'near'),
 ('cinca','Cinca',r'\bCinca\b',r'^(Río )?Cinca$',R,'far'),
 ('francoli','Francolí',r'\bFrancolí\b',r'^(Riu |el |El )?Francol[ií]$',R,'near'),
 ('guadalquivir','Guadalquivir',r'\bGuadalquivir\b',r'^(Río )?Guadalquivir$',R,'far'),
 ('guadiana','Guadiana',r'\bGuadiana\b',r'^(Río |Rio )?Guadiana$',R,'far'),
 ('segre','Segre',r'\bSegre\b',r'^(Riu |Río |el |El )?Segre$',R,'far'),
 ('mondego','Mondego',r'\bMondego\b',r'^(Rio )?Mondego$',R,'far'),
 ('dao','Dão',r'\bDão (river|River)\b|\bthe Dão\b',r'^(Rio )?Dão$',R,'near'),
 ('sado','Sado',r'\bSado\b',r'^(Rio )?Sado$',R,'far'),
 ('lima','Lima',r'\bLima (river|River)\b|\bthe Lima\b',r'^(Rio )?Lima$|^(Río )?Limia$',R,'far'),
 # Eastern Mediterranean, Caucasus
 ('alazani','Alazani',r'\bAlazani\b',r'^(Alazani|ალაზანი)$',R,'far'),
 # United States
 ('columbia','Columbia River',r'\bColumbia River\b(?! Gorge)|\bthe Columbia\b',r'^Columbia River$',R,'far'),
 ('snake','Snake River',r'\bSnake River\b',r'^Snake River$',R,'far'),
 ('yakima','Yakima River',r'\bYakima River\b|\bthe Yakima\b',r'^Yakima River$',R,'far'),
 ('walla-walla','Walla Walla River',r'\bWalla Walla River\b',r'^Walla Walla River$',R,'near'),
 ('willamette','Willamette River',r'\bWillamette River\b|\bthe Willamette\b',r'^Willamette River$',R,'far'),
 ('tualatin','Tualatin River',r'\bTualatin River\b',r'^Tualatin River$',R,'near'),
 ('long-tom','Long Tom River',r'\bLong Tom River\b',r'^Long Tom River$',R,'near'),
 ('umpqua','Umpqua River',r'\bUmpqua River\b|\bthe Umpqua\b',r'^((North|South) )?Umpqua River$',R,'far'),
 ('rogue','Rogue River',r'\bRogue River\b|\bthe Rogue\b',r'^Rogue River$',R,'far'),
 ('applegate','Applegate River',r'\bApplegate River\b',r'^Applegate River$',R,'near'),
 ('klamath','Klamath River',r'\bKlamath River\b',r'^Klamath River$',R,'near'),
 ('russian','Russian River',r'\bRussian River\b',r'^Russian River$',R,'far'),
 ('dry-creek','Dry Creek',r'\bDry Creek\b',r'^Dry Creek$',S,'near'),
 ('napa','Napa River',r'\bNapa River\b',r'^Napa River$',R,'far'),
 ('putah','Putah Creek',r'\bPutah Creek\b',r'^Putah Creek$',S,'near'),
 ('cache','Cache Creek',r'\bCache Creek\b',r'^Cache Creek$',S,'near'),
 ('navarro','Navarro River',r'\bNavarro River\b',r'^Navarro River$',R,'near'),
 ('eel','Eel River',r'\bEel River\b',r'^Eel River$',R,'near'),
 ('trinity','Trinity River',r'\bTrinity River\b',r'^Trinity River$',R,'near'),
 ('sacramento','Sacramento River',r'\bSacramento River\b|\bthe Sacramento\b',r'^Sacramento River$',R,'far'),
 ('san-joaquin','San Joaquin River',r'\bSan Joaquin River\b',r'^San Joaquin River$',R,'far'),
 ('mokelumne','Mokelumne River',r'\bMokelumne River\b',r'^Mokelumne River$',R,'near'),
 ('cosumnes','Cosumnes River',r'\bCosumnes River\b',r'^Cosumnes River$',R,'near'),
 ('stanislaus','Stanislaus River',r'\bStanislaus River\b',r'^Stanislaus River$',R,'near'),
 ('salinas','Salinas River',r'\bSalinas River\b|\bthe Salinas\b',r'^Salinas River$',R,'far'),
 ('arroyo-seco','Arroyo Seco',r'\bArroyo Seco Creek\b',r'^Arroyo Seco$',S,'near'),
 ('san-benito','San Benito River',r'\bSan Benito River\b',r'^San Benito River$',R,'near'),
 ('pajaro','Pajaro River',r'\bPajaro River\b',r'^Pajaro River$',R,'near'),
 ('estrella','Estrella River',r'\bEstrella River\b',r'^Estrella River$',R,'near'),
 ('santa-ynez','Santa Ynez River',r'\bSanta Ynez River\b',r'^Santa Ynez River$',R,'far'),
 ('santa-maria','Santa Maria River',r'\bSanta Maria River\b',r'^Santa Maria River$',R,'near'),
 ('clear-lake','Clear Lake',r'\bClear Lake\b',r'^Clear Lake$',L,'near'),
 ('lopez-lake','Lopez Lake',r'\bLopez Lake\b',r'^Lopez Lake$',L,'near'),
 ('trinity-lake','Trinity Lake',r'\bTrinity Lake\b',r'^Trinity Lake$',L,'near'),
 ('lewiston-lake','Lewiston Lake',r'\bLewiston Lake\b',r'^Lewiston Lake$',L,'near'),
 ('lake-chelan','Lake Chelan',r'\bLake Chelan\b',r'^Lake Chelan$',L,'near'),
 ('seneca','Seneca Lake',r'\bSeneca Lake\b',r'^Seneca Lake$',L,'far'),
 ('cayuga','Cayuga Lake',r'\bCayuga Lake\b',r'^Cayuga Lake$',L,'far'),
 ('keuka','Keuka Lake',r'\bKeuka Lake\b|\bKeuka\b',r'^Keuka Lake$',L,'far'),
 ('canandaigua','Canandaigua Lake',r'\bCanandaigua\b',r'^Canandaigua Lake$',L,'far'),
 ('lake-erie','Lake Erie',r'\bLake Erie\b',r'^Lake Erie$',L,'far'),
 ('lake-ontario','Lake Ontario',r'\bLake Ontario\b',r'^Lake Ontario$',L,'far'),
 ('lake-michigan','Lake Michigan',r'\bLake Michigan\b|\bGrand Traverse Bay\b',r'^Lake Michigan$',L,'far'),
 ('lake-champlain','Lake Champlain',r'\bLake Champlain\b|\bChamplain\b',r'^Lake Champlain$',L,'far'),
 ('hudson','Hudson River',r'\bHudson River\b|\bthe Hudson\b',r'^Hudson River$',R,'far'),
 ('niagara','Niagara River',r'\bNiagara River\b',r'^Niagara River$',R,'far'),
 ('ohio','Ohio River',r'\bOhio River\b',r'^Ohio River$',R,'far'),
 ('kanawha','Kanawha River',r'\bKanawha River\b',r'^Kanawha River$',R,'far'),
 ('mississippi','Mississippi River',r'\bMississippi River\b',r'^Mississippi River$',R,'far'),
 ('missouri','Missouri River',r'\bMissouri River\b',r'^Missouri River$',R,'far'),
 ('arkansas','Arkansas River',r'\bArkansas River\b',r'^Arkansas River$',R,'far'),
 ('delaware','Delaware River',r'\bDelaware River\b',r'^Delaware River$',R,'far'),
 ('potomac','Potomac River',r'\bPotomac River\b|\bthe Potomac\b',r'^Potomac River$',R,'far'),
 ('shenandoah','Shenandoah River',r'\bShenandoah River\b',r'^((North|South) Fork )?Shenandoah River$',R,'far'),
 ('rio-grande','Rio Grande',r'\bRio Grande\b',r'^Rio Grande$',R,'far'),
 # Canada
 ('okanagan-lake','Okanagan Lake',r'\bOkanagan Lake\b|\bthe Okanagan\b',r'^Okanagan Lake$',L,'far'),
 ('skaha','Skaha Lake',r'\bSkaha\b',r'^Skaha Lake$',L,'near'),
 ('similkameen','Similkameen River',r'\bSimilkameen River\b|\bthe Similkameen\b',r'^Similkameen River$',R,'far'),
 ('fraser','Fraser River',r'\bFraser River\b',r'^Fraser River$',R,'far'),
 ('welland','Welland River',r'\bWelland River\b',r'^Welland River$',R,'near'),
 ('grand-on','Grand River',r'\bGrand River\b',r'^Grand River$',R,'near'),
 # Southern hemisphere
 ('murray','Murray River',r'\bMurray River\b|\bthe Murray\b',r'^Murray River$|^River Murray$',R,'far'),
 ('darling','Darling River',r'\bDarling River\b',r'^Darling River$',R,'far'),
 ('murrumbidgee','Murrumbidgee River',r'\bMurrumbidgee\b',r'^Murrumbidgee River$',R,'far'),
 ('hunter','Hunter River',r'\bHunter River\b|\bthe Hunter\b',r'^Hunter River$',R,'far'),
 ('hastings','Hastings River',r'\bHastings River\b',r'^Hastings River$',R,'near'),
 ('lachlan','Lachlan River',r'\bLachlan River\b',r'^Lachlan River$',R,'far'),
 ('swan','Swan River',r'\bSwan River\b',r'^Swan River$',R,'far'),
 ('margaret','Margaret River',r'\bMargaret River\b(?! region| wine)',r'^Margaret River$',R,'near'),
 ('frankland','Frankland River',r'\bFrankland River\b',r'^Frankland River$',R,'near'),
 ('yarra','Yarra River',r'\bYarra River\b|\bthe Yarra\b',r'^Yarra River$|^Birrarung$',R,'far'),
 ('goulburn','Goulburn River',r'\bGoulburn River\b',r'^Goulburn River$',R,'far'),
 ('nagambie','Lake Nagambie',r'\bNagambie Lake\b|\bLake Nagambie\b',r'^Lake Nagambie$',L,'near'),
 ('angas','Angas River',r'\bAngas River\b',r'^Angas River$',R,'near'),
 ('bremer','Bremer River',r'\bBremer River\b',r'^Bremer River$',R,'near'),
 ('derwent','Derwent River',r'\bDerwent\b',r'^(River )?Derwent$|^Derwent River$',R,'far'),
 ('tamar','Tamar River',r'\bTamar\b',r'^(kanamaluka / )?Tamar River$|^kanamaluka.*Tamar',R,'far'),
 ('wairau','Wairau River',r'\bWairau River\b|\bthe Wairau\b',r'^Wairau River$',R,'far'),
 ('awatere','Awatere River',r'\bAwatere River\b|\bthe Awatere\b',r'^Awatere River$',R,'far'),
 ('waipara','Waipara River',r'\bWaipara River\b',r'^Waipara River$',R,'near'),
 ('clutha','Clutha River',r'\bClutha\b',r'^Clutha River$|^Clutha River / Mata-Au$',R,'far'),
 ('kawarau','Kawarau River',r'\bKawarau\b',r'^Kawarau River$',R,'far'),
 ('dunstan','Lake Dunstan',r'\bLake Dunstan\b',r'^Lake Dunstan$',L,'far'),
 ('wanaka','Lake Wanaka',r'\bLake Wanaka\b',r'^Lake Wānaka$|^Lake Wanaka$',L,'far'),
 ('tukituki','Tukituki River',r'\bTukituki\b',r'^Tukituki River$',R,'near'),
 ('ngaruroro','Ngaruroro River',r'\bNgaruroro\b',r'^Ngaruroro River$',R,'near'),
 ('breede','Breede River',r'\bBreede\b',r'^Breede River$|^Breërivier$|^Breede$',R,'far'),
 ('olifants','Olifants River',r'\bOlifants River\b',r'^Olifants River$|^Olifantsrivier$',R,'far'),
 ('berg','Berg River',r'\bBerg River\b',r'^Berg River$|^Bergrivier$',R,'far'),
 ('orange','Orange River',r'\bOrange River\b',r'^Orange River$|^Oranjerivier$|^Gariep$',R,'far'),
 ('klein-river','Klein River',r'\bKlein River\b',r'^Klein River$|^Kleinrivier$',R,'near'),
 ('bot-river','Bot River',r'\bBot River\b(?! ward)',r'^Bot River$|^Botrivier$',R,'near'),
 ('duivenhoks','Duivenhoks River',r'\bDuivenhoks\b',r'^Du[iy][vw]enhoks ?([Rr]iver|rivier)$',R,'near'),
 ('maipo','Maipo River',r'\bthe Maipo\b|\bMaipo River\b',r'^Río Maipo$',R,'far'),
 ('rapel','Rapel River',r'\bthe Rapel\b|\bRapel River\b',r'^Río Rapel$',R,'far'),
 ('cachapoal','Cachapoal River',r'\bCachapoal River\b|\bthe Cachapoal\b',r'^Río Cachapoal$',R,'far'),
 ('tinguiririca','Tinguiririca River',r'\bTinguiririca\b',r'^Río Tinguiririca$',R,'far'),
 ('teno','Teno River',r'\bthe Teno\b|\bTeno River\b',r'^Río Teno$',R,'far'),
 ('lontue','Lontué River',r'\bthe Lontué\b|\bLontué River\b',r'^Río Lontué$',R,'far'),
 ('maule','Maule River',r'\bthe Maule\b|\bMaule River\b',r'^Río Maule$',R,'far'),
 ('itata','Itata River',r'\bthe Itata\b|\bItata River\b',r'^Río Itata$',R,'far'),
 ('biobio','Biobío River',r'\bthe Bío ?Bío\b|\bBiobío River\b',r'^Río Biobío$|^Río Bío Bío$',R,'far'),
 ('elqui','Elqui River',r'\bthe Elqui\b|\bElqui River\b',r'^Río Elqui$',R,'far'),
 ('limari','Limarí River',r'\bthe Limarí\b|\bLimarí River\b',r'^Río Limarí$',R,'far'),
 ('aconcagua','Aconcagua River',r'\bAconcagua River\b|\bthe Aconcagua\b',r'^Río Aconcagua$',R,'far'),
 ('mendoza','Mendoza River',r'\bMendoza River\b|\bRío Mendoza\b',r'^Río Mendoza$',R,'far'),
 ('tunuyan','Tunuyán River',r'\bTunuyán River\b|\bRío Tunuyán\b',r'^Río Tunuyán$',R,'far'),
 ('san-juan-ar','San Juan River',r'\bSan Juan River\b|\bRío San Juan\b',r'^Río San Juan$',R,'far'),
 ('calchaqui','Calchaquí River',r'\bCalchaquí River\b|\bRío Calchaquí\b',r'^Río Calchaquí$',R,'far'),
 ('rio-negro','Río Negro',r'\bthe Negro River\b|\bRío Negro river\b',r'^Río Negro$',R,'far'),
]
assert len({g[0] for g in GAZ})==len(GAZ)
# The countries a water runs through, where more than one: a page elsewhere that names it (Paso Robles's "Rhône-style",
# Bucelas's "Rhine Riesling") does not draw it. Others keep the country most of their pages are in.
LANDS={'danube':{'austria','hungary','germany','slovakia','croatia','serbia','romania','bulgaria'},'rhine':{'germany','france','switzerland','austria','netherlands'},
       'moselle':{'france','germany','luxembourg'},'duero':{'spain','portugal'},'tagus':{'spain','portugal'},'mino':{'spain','portugal'},
       'tisza':{'hungary','ukraine','serbia','slovakia'},'isonzo':{'italy','slovenia'},'elbe':{'germany','czechia'},'drava':{'austria','slovenia','croatia','hungary'},
       'mur':{'austria','slovenia','hungary','croatia'},'columbia':{'united-states','canada'},'niagara':{'united-states','canada'},'lake-erie':{'united-states','canada'},
       'lake-ontario':{'united-states','canada'},'similkameen':{'canada','united-states'},'lake-constance':{'germany','austria','switzerland'},
       'lake-geneva':{'switzerland','france'},'neusiedler-see':{'austria','hungary'},'saar':{'germany','france'},'lake-champlain':{'united-states','canada'}}
# The name a river goes by on a country's own pages, where it differs from the English one (Germany's Mosel region).
LOCAL={'moselle':{'germany':'Mosel'}}
# Where to look, for waters named only by places with no outline of their own (Canada's GIs) or a vast one: the area
# around the vineyards, west, south, east, north. These steer the download only; what is drawn is OpenStreetMap's.
SEARCH={'okanagan-lake':[-120.0,49.0,-119.2,50.4],'skaha':[-119.75,49.25,-119.45,49.5],'similkameen':[-120.6,48.9,-119.4,49.6],
        'niagara':[-79.2,42.8,-78.85,43.3],'welland':[-79.7,42.85,-79.0,43.15],'fraser':[-123.3,48.95,-121.3,49.4],
        'orange':[20.5,-29.4,24.4,-28.1],'mur':[16.0,46.2,17.1,46.9],'lot':[0.5,44.25,1.5,44.75],'lake-constance':[8.9,47.4,9.9,47.85],
        'neckar':[8.4,48.5,9.7,49.5],'berg':[18.5,-33.95,19.15,-32.6],'jiloca':[-1.7,40.3,-1.1,41.4],'cinca':[-0.1,41.3,0.5,42.2]}
RX={g[0]:re.compile(g[2]) for g in GAZ}
BY={g[0]:g for g in GAZ}

def texts():
    """What each page says in words: its name, blurb and key facts (the climate and land readings are generic)."""
    T={}
    for f in sorted(glob.glob(os.path.join(ROOT,'regions','blurbs','*.json'))):
        for k,v in json.load(open(f,encoding='utf-8')).items():
            if isinstance(v,dict) and v.get('text') and not v.get('cut'): T[k]=v['text']
    for f in sorted(glob.glob(os.path.join(ROOT,'regions','keyfacts','*.json'))):
        for k,v in json.load(open(f,encoding='utf-8')).items():
            fs=v.get('facts') if isinstance(v,dict) else v
            if isinstance(fs,list): T[k]=T.get(k,'')+' '+' '.join(x for x in fs if isinstance(x,str))
    tree=json.load(open(os.path.join(ROOT,'regions','tree.json'),encoding='utf-8'))['nodes']
    for k,n in tree.items(): T[k]=n.get('name','')+'. '+T.get(k,'')
    return T

def mentions(T=None):
    """{water id: set of places whose page names it}"""
    T=T or texts(); out=collections.defaultdict(set)
    for k,t in T.items():
        for w,rx in RX.items():
            if rx.search(t): out[w].add(k)
    for w,ps in out.items():
        c=collections.Counter(p.split('/')[0] for p in ps)
        keep=LANDS.get(w) or {c.most_common(1)[0][0]}
        out[w]={p for p in ps if p.split('/')[0] in keep}
    return out

def shown(V,men,parent):
    """{view id: [water ids]}: a view shows what its own place, the places on it or the places around it name."""
    out={}
    for vid,v in V.items():
        if vid=='world': continue
        near={vid,*(it['id'] for it in v.get('items',[]))}
        ws=[w for w,ps in men.items() if ps&near]
        if ws: out[vid]=sorted(ws)
    return out

def inherited(V,sh,parent):
    """A view also shows what the views above it show (the Danube from Austria's view runs on through Kremstal's); attach()
    keeps only the waters that reach into the view."""
    def chain(n):
        p=parent.get(n)
        while p and p not in V: p=parent.get(p)
        return [p]+chain(p) if p else []
    out={}
    for vid in V:
        if vid=='world': continue
        ws=set(sh.get(vid,[]))
        for a in chain(vid): ws|=set(sh.get(a,[]))
        if ws: out[vid]=sorted(ws)
    return out

# ---- fetching
def overpass(q):
    body=urllib.parse.urlencode({'data':q}).encode()
    for url in ('https://overpass.private.coffee/api/interpreter','https://overpass-api.de/api/interpreter'):   # private.coffee (kumi) first: overpass-api.de runs at capacity in busy hours
        for k in range(3):
            try:
                rq=urllib.request.Request(url,data=body,headers={'User-Agent':'AppellationAtlas/1.0 (non-commercial wine atlas; build script)'})
                with urllib.request.urlopen(rq,timeout=200) as r: return json.loads(r.read())
            except Exception as e:
                print('  retry',k,url,str(e)[:80],flush=True); time.sleep(10*(k+1))
    raise RuntimeError('Overpass did not answer')

def fetch(only=None):
    os.makedirs(CACHE,exist_ok=True)
    views={}
    for f in glob.glob(os.path.join(ROOT,'build','atlas','geo','views','*.json')):
        v=json.load(open(f,encoding='utf-8')); views[v['id']]=v
    idx=json.load(open(os.path.join(ROOT,'build','atlas','geo','index.json'),encoding='utf-8'))['places']
    parent={k:(v['parent'] if v['parent']!='world' else None) for k,v in idx.items()}
    men=mentions(); sh=shown(views,men,parent)
    from shapely import wkb
    shapes=json.load(open(os.path.join(ROOT,'build','atlas','shapes.json')))
    for w,(wid,name,_,osm,kind,reach) in ((g[0],g) for g in GAZ):
        if only and w not in only: continue
        p=os.path.join(CACHE,w+'.json')
        if os.path.exists(p) and not only: continue
        vs=[views[vid] for vid,ws in sh.items() if w in ws]
        if not vs: continue
        # around the places that name it: about 100 km out for a long river (the Loire's names run from Muscadet to the Forez,
        # so their boxes cover its wine stretch), 15 km for a creek whose name repeats across a county
        px,py=(1.3,1.0) if reach=='far' else (.2,.15)
        boxes=[SEARCH[w]] if w in SEARCH else []
        for n in ([] if w in SEARCH else men[w]):
            while n and n not in shapes: n=parent.get(n)   # a place with no outline of its own (the Okanagan benches): the nearest one above it
            if not n: continue
            b=wkb.loads(shapes[n],hex=True).bounds
            if (b[2]-b[0])*(b[3]-b[1])>40: continue   # a whole country or state
            boxes.append([b[0]-px,b[1]-py,b[2]+px,b[3]+py])
        if not boxes: continue
        b=[min(x[0] for x in boxes),min(x[1] for x in boxes),max(x[2] for x in boxes),max(x[3] for x in boxes)]
        bb=f'{b[1]:.3f},{b[0]:.3f},{b[3]:.3f},{b[2]:.3f}'
        nm=f'["name"~"{osm}",i]'
        if kind==L: q=f'[out:json][timeout:180];(way["natural"="water"]{nm}({bb});relation["natural"="water"]{nm}({bb}););out geom;'
        else:
            wt='^(river|stream)$' if kind==S else '^river$'
            q=f'[out:json][timeout:180];(way["waterway"~"{wt}"]{nm}({bb});way["waterway"~"{wt}"]["name:en"~"{osm}",i]({bb}););out geom;'
        print(w,bb,flush=True)
        try: d=overpass(q)
        except RuntimeError as e: print('  FAILED',w,flush=True); continue
        json.dump(dict(id=w,name=name,kind=kind,box=b,query=q,fetched=time.strftime('%Y-%m-%d'),elements=d.get('elements',[])),open(p,'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
        print('  ',len(d.get('elements',[])),'elements',flush=True); time.sleep(1.5)

# ---- building
def geometry(w):
    """A water's shapely geometry from its cached elements: lines for rivers, polygons for lakes."""
    import shapely
    from shapely.geometry import LineString,MultiLineString,Polygon
    from shapely.ops import linemerge,polygonize,unary_union
    p=os.path.join(CACHE,w+'.json')
    if not os.path.exists(p): return None
    d=json.load(open(p,encoding='utf-8'))
    if d['kind']!=L:
        ls=[LineString([(n['lon'],n['lat']) for n in e['geometry']]) for e in d['elements'] if e['type']=='way' and len(e.get('geometry') or [])>1]
        return linemerge(ls) if ls else None
    polys=[]
    for e in d['elements']:
        if e['type']=='way' and len(e.get('geometry') or [])>3:
            polys.append(Polygon([(n['lon'],n['lat']) for n in e['geometry']]))
        elif e['type']=='relation':
            outer=[LineString([(n['lon'],n['lat']) for n in m['geometry']]) for m in e.get('members',[]) if m.get('role')=='outer' and len(m.get('geometry') or [])>1]
            inner=[LineString([(n['lon'],n['lat']) for n in m['geometry']]) for m in e.get('members',[]) if m.get('role')=='inner' and len(m.get('geometry') or [])>1]
            o=unary_union(list(polygonize(unary_union(outer)))) if outer else None
            if o is None or o.is_empty: continue
            if inner:
                i_=unary_union(list(polygonize(unary_union(inner))))
                if not i_.is_empty: o=o.difference(i_)
            polys.append(o)
    polys=[q.buffer(0) for q in polys if not q.is_empty]
    return unary_union(polys) if polys else None

def attach(V,parent):
    """Add each view's rivers and lakes to it: {'water': [{'n': name, 'k': 'r'|'l', 'p': [flat lon,lat rings or lines], 'a': [anchor lon,lat, next lon,lat]}]}.
    Lines are clipped to the view's box and thinned to about a pixel at the view's closest zoom (8 times its opening size)."""
    import shapely
    from shapely.geometry import box as Box
    men=mentions(); sh=inherited(V,shown(V,men,parent),parent); G={}; used=collections.defaultdict(set)
    for vid,ws in sh.items():
        v=V[vid]; b=v['box']
        if not b: continue   # the world view has no box
        pad=.08*max(b[2]-b[0],b[3]-b[1]); clipbox=Box(b[0]-pad,b[1]-pad,b[2]+pad,b[3]+pad)
        tol=max(v['half'])*6371e3/2400/111e3   # degrees in a pixel at the closest zoom, roughly
        out=[]
        for w in ws:
            if w not in G: G[w]=geometry(w)
            g=G[w]
            if g is None or g.is_empty: continue
            c=g.intersection(clipbox)
            if c.is_empty: continue
            c=c.simplify(tol,preserve_topology=False)
            kind=BY[w][4]
            if kind==L:
                ps=[q for q in getattr(c,'geoms',[c]) if q.geom_type=='Polygon' and q.area>(tol*6)**2]
                if not ps: continue
                rings=[[round(x,5) for xy in q.exterior.coords for x in xy] for q in ps]
                big=max(ps,key=lambda q:q.area); a=big.representative_point()
                out.append(dict(n=LOCAL.get(w,{}).get(vid.split('/')[0],BY[w][1]),k='l',p=rings,a=[round(a.x,5),round(a.y,5)]))
            else:
                ls=[q for q in getattr(c,'geoms',[c]) if q.geom_type=='LineString' and len(q.coords)>1]
                if not ls: continue
                lines=[[round(x,5) for xy in q.coords for x in xy] for q in ls]
                inner=Box(b[0],b[1],b[2],b[3]); best=max(ls,key=lambda q:q.intersection(inner).length)
                m=best.intersection(inner); m=max(getattr(m,'geoms',[m]),key=lambda q:q.length) if not m.is_empty else best
                if m.geom_type!='LineString': m=best
                L_=m.length; a=m.interpolate(.5,normalized=True); a2=m.interpolate(min(L_,m.project(a)+L_*.04))
                out.append(dict(n=LOCAL.get(w,{}).get(vid.split('/')[0],BY[w][1]),k='r',p=lines,a=[round(a.x,5),round(a.y,5),round(a2.x,5),round(a2.y,5)]))
            used[w].add(vid)
        if out: v['water']=out
    return used

if __name__=='__main__':
    cmd=sys.argv[1] if len(sys.argv)>1 else ''
    if cmd=='fetch': fetch(set(sys.argv[2:]) or None)
    elif cmd=='list':
        for w,ps in sorted(mentions().items(),key=lambda x:-len(x[1])): print(len(ps),w,' '.join(sorted(ps)[:6]))
    else: print(__doc__)
