-- 170. Порахувати кількість замовлень у кожному місяці (рік–місяць) і 
-- відсортувати від найновіших до найстаріших.

SELECT Extract(month from order_date) as month
       ,Extract (year from order_date) as year
	   ,COUNT(*) as count_orders
FROM orders
GROUP BY Extract(month from order_date) ,Extract (year from order_date)
ORDER BY year, month DESC

-- 171. Знайти ТОП-5 клієнтів за загальним обсягом продажів.

SELECT customer_id
       ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as revenue
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id
Order by revenue DESC
LIMIT 5

-- 172. Визначити середню кількість товарів у замовленні для кожного місяця.

WITH level1 as(SELECT EXTRACT(month from order_date) as month
       ,extract (year from order_date) as year
	   ,order_id
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIN order_details USING(order_id)
GROUP BY EXTRACT(month from order_date), extract (year from order_date), order_id)
SELECT year
       ,month
	   ,ROUND(AVG(sum_quantity)::numeric,2) as avg_quantity
FROM level1
GROUP BY year, month
ORDER BY year DESC, month DESC

-- 173. Для кожного клієнта знайти дату його першого замовлення і дату його
-- останнього замовлення, а також кількість днів між ними.

WITH level1 as(SELECT customer_id
       ,FIRST_value (order_date) OVER (partition by customer_id order by order_date) as first_date
	   ,FIRST_value (order_date) Over (partition by customer_id order by order_date DESC) as last_date
FROM orders
JOIN order_details USING(order_id))
SELECT DISTINCT customer_id
       ,last_date - first_date as days_between
FROM level1
ORDER BY days_between DESC

-- 174. Для кожного клієнта знайти замовлення, у якому він витратив найбільше грошей (максимальний чек). 

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id),
level2 as(SELECT customer_id
       ,order_id
	   ,sum_chek
       ,MAX(sum_chek) OVER (partition by customer_id) as max_sum_chek
FROM level1)
SELECT *
FROM level2
WHERE sum_chek = max_sum_chek

-- 175. Знайти клієнтів, які роблять замовлення щомісяця без пропусків
-- від їхнього першого до останнього замовлення.
--Тобто якщо клієнт має замовлення, наприклад, у 1997-04 → 1997-05 → 1997-06 → 1997-07 то він підходить.
-- А якщо є хоч один пропуск (наприклад, немає 1997-06) — він не підходить.

WITH level1 as(SELECT DISTINCT date_trunc('month', order_date) as date
       ,customer_id
FROm orders),
level2 as(SELECT customer_id
       ,date
	   ,LEAD(date) OVER (partition by customer_id order by date) as next_date
FROM level1),
level3 as(SELECT *
       ,case when date + interval '1 month' = next_date THEN 1 ELSE 0 END as flag_date
	   ,COUNT(*) OVER(partition by customer_id) as real_count_order
FROM level2
where next_date is not null),
level4 as(SELECT *
       ,SUM(flag_date) OVER (partition by customer_id) as sum_flag
FROM level3)
SELECT *
FROm level4
WHERE real_count_order = sum_flag

-- 176. Знайти клієнтів, у яких кожне наступне замовлення дорожче, ніж попереднє (за сумою чека).

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id,order_date),
level2 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > next_chek THEN 1 ELSE 0 END as flag_chek
	   ,COUNT(*) OVER (partition by customer_id) as real_count_order
FROM level2
WHere next_chek is not null),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level3)
SELECT *
FROM level4
WHERE real_count_order = sum_flag_chek

-- 177. “Клієнти з аномальною поведінкою: відхилення чека від середнього”
-- Потрібно знайти клієнтів, у яких є хоча б одне замовлення, де сума чека
-- відхиляється від їхнього середнього чека більше, ніж на 50%

WITH level1 as(SELECT customer_id 
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id ,order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_per_customer
FROM level1),
level3 as(SELECT customer_id
       ,order_id
	   ,sum_chek
	   ,avg_chek_per_customer
	   ,ROUND((ABS(sum_chek - avg_chek_per_customer) / avg_chek_per_customer),2) as coef 
FROM level2)
SELECT *
FROM level3
WHERE coef > 0.5

-- 178. “Замовлення з підозрілим розкидом цін: нестабільні мікс-тотали”
-- Замовлення вважається підозрілим, якщо:
-- 1) Воно містить 2+ різних товарів
-- 2) При цьому середня ціна за одиницю дуже сильно відхиляється
-- від середньої ціни по цьому ж клієнту (> 60%)

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(AVG(unit_price * (1-discount))::numeric,2) as avg_price
       ,count(DISTINCT product_id) as unik_count_orders
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id,order_id),
level2 as(SELECT *
       ,ROUND(AVG(avg_price) OVER (partition by customer_id)::numeric,2) as customer_avg_price
FROM level1),
level3 as(SELECT customer_id
       ,order_id
	   ,unik_count_orders
	   ,avg_price
	   ,customer_avg_price
	   ,ROUND(ABS((avg_price - customer_avg_price) / customer_avg_price),2) as deviation_ratio
FROM level2)
SELECT *
FROM level3 
WHERE unik_count_orders >= 2 AND deviation_ratio > 0.6

-- 179. У клієнтів зазвичай є свій "ціновий патерн":
-- вони купують товари приблизно одного рівня ціни, або в дуже схожому діапазоні.
-- Але нам треба знайти клієнтів, у яких у середині їхньої історії покупок з'явився
-- різкий «обрив» або «злам» ціни.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
       ,ROUND(AVG(unit_price * (1-discount))::numeric,2) as avg_price
	   ,COUNT(*) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
	   ,COUNT(*) OVER (partition by customer_id) / 2 as middle_point
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id,order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point Then 'second_half'
	   END as halfs
FROM level1),
level3 as(SELECT customer_id
       ,ROUND(AVG(avg_price) FILTER (where halfs = 'first_half')::numeric,2) as avg_price_first_half
	   ,ROUND(AVG(avg_price) FILTER (where halfs = 'second_half')::numeric,2) as avg_price_second_half
FROM level2
GROUP BY customer_id),
level4 as(SELECT customer_id
       ,avg_price_first_half
	   ,avg_price_second_half
	   ,ROUND((ABS(avg_price_second_half - avg_price_first_half) / avg_price_first_half),2) as deviation_ratio
FROM level3)
SELECT *
       ,case when avg_price_second_half >= avg_price_first_half THEN 'growth'
	   when avg_price_second_half < avg_price_first_half THEN 'drop'
	   END as trend
FROM level4
Where deviation_ratio > 0.7

-- 180. У нормі клієнти з часом роблять замовлення з більш-менш стабільною частотою.
-- Але треба знайти тих, у кого інтервали між замовленнями різко ростуть від одних періодів до інших.

WITH level1 as(SELECT DISTINCT order_date
       ,customer_id
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,order_date
       ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
FROM level1),
level3 as(SELECT *
       ,order_date - prev_date as interval
	   ,COUNT(*) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER() OVER(partition by customer_id order by order_date) as rn
	   ,COUNT(*) OVER (partition by customer_id) / 2 as middle_point
FROm level2
WHERE prev_date is not null),
level4 as(SELECT *
       ,case when  rn <= middle_point THEN 'first_half'
	   when rn > middle_point Then 'second_half'
	   END as halfs
FROM level3),
level5 as(SELECT customer_id
       ,ROUND(AVG(interval) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_interval_first_half
	   ,ROUND(AVG(interval) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_interval_second_half
FROM level4
GROUP BY customer_id)
SELECT *
FROM level5
WHERE avg_interval_second_half > avg_interval_first_half * 2

-- 181. “Знайти клієнтів, у яких загальна поведінка повністю зміщена від домінантної категорії (>70%).”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,category_name
	   ,COUNT(category_name) OVER (partition by customer_id,category_name) as count_orders_per_category
FROm orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN categories USING (category_id)),
level2 as(SELECT DISTINCT category_name
       ,customer_id
	   ,count_orders_per_category
	   ,MAX(count_orders_per_category) OVER (partition by customer_id) as dominant_category
	   ,COUNT(count_orders_per_category) OVER (partition by customer_id) as total_count
FROM level1
ORDER BY customer_id, category_name),
level3 as(SELECT *
       ,total_count - dominant_category as non_dominant
       ,ROUND(((total_count - dominant_category::numeric)  / total_count::numeric),2) as ratio
FROm level2)
SELECT *
FROM level3
WHERE ratio > 0.7



	   